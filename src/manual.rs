use crate::config::Config;
use crate::db;

use std::collections::BTreeMap;
use std::fs::{create_dir_all, read_to_string, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use tr::tr;

#[derive(Serialize, Deserialize, Default, Debug, Clone)]
pub struct ManualPkgInfo {
    pub manually_installed: bool,
    pub manually_uninstalled: bool,
    pub version: String,
    #[serde(default)]
    pub provides: Vec<String>,
    #[serde(default)]
    pub timestamp: Option<String>,
}

#[derive(Serialize, Deserialize, Default, Debug, Clone)]
#[serde(transparent)]
pub struct ManualState {
    pub packages: BTreeMap<String, ManualPkgInfo>,
}

impl ManualState {
    pub fn is_manually_installed(&self, pkg: &str) -> bool {
        self.packages
            .get(pkg)
            .map(|i| i.manually_installed)
            .unwrap_or(false)
    }

    pub fn is_manually_uninstalled(&self, pkg: &str) -> bool {
        self.packages
            .get(pkg)
            .map(|i| i.manually_uninstalled)
            .unwrap_or(false)
    }
}

/// Load manual state from TOML file
pub fn load_manual_state(config: &Config) -> Result<Option<ManualState>> {
    let file = match read_to_string(&config.manual_path) {
        Ok(file) => file,
        _ => return Ok(None),
    };
    let state = ManualState::deserialize(toml::Deserializer::parse(&file)?)
        .with_context(|| tr!("invalid toml: {}", config.manual_path.display()))?;
    Ok(Some(state))
}

/// Save manual state with atomic temp-file write
pub fn save_manual_state(config: &Config, state: &ManualState) -> Result<()> {
    create_dir_all(&config.state_dir).with_context(|| {
        tr!(
            "failed to create state directory: {}",
            config.state_dir.display()
        )
    })?;

    let mut temp = config.manual_path.to_owned();
    temp.set_extension("toml.tmp");

    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&temp);

    let mut file =
        file.with_context(|| tr!("failed to create temporary file: {}", temp.display()))?;

    let toml_str = toml::to_string(&state).unwrap();

    file.write_all(toml_str.as_bytes())
        .with_context(|| tr!("failed to write to temporary file: {}", temp.display()))?;

    drop(file);

    std::fs::rename(&temp, &config.manual_path).with_context(|| {
        tr!(
            "failed to rename '{temp}' to '{manual_toml}'",
            temp = temp.display(),
            manual_toml = config.manual_path.display()
        )
    })?;

    Ok(())
}

/// Mark a package as manually installed: create fake DB entry + add to IgnorePkg + persist
pub fn mark_manually_installed(
    config: &Config,
    pkg: &str,
    version: &str,
    provides: &[String],
    depends: &[String],
    state: &mut ManualState,
) -> Result<()> {
    db::create_fake_local_db_entry(config, pkg, version, provides, depends, 0, 0, &[])?;

    let timestamp = chrono::Utc::now().to_rfc3339();

    state.packages.insert(
        pkg.to_string(),
        ManualPkgInfo {
            manually_installed: true,
            manually_uninstalled: false,
            version: version.to_string(),
            provides: provides.to_vec(),
            timestamp: Some(timestamp),
        },
    );

    save_manual_state(config, state)?;
    Ok(())
}

/// Mark a package as manually uninstalled: remove DB entry + AssumeInstalled + persist
pub fn mark_manually_uninstalled(
    config: &Config,
    pkg: &str,
    state: &mut ManualState,
) -> Result<()> {
    // Remove all matching local DB entries
    let entries = db::find_local_db_entries(config, pkg)?;
    for (name, version) in &entries {
        db::remove_local_db_entry(config, name, version)?;
    }

    let timestamp = chrono::Utc::now().to_rfc3339();

    state.packages.insert(
        pkg.to_string(),
        ManualPkgInfo {
            manually_installed: false,
            manually_uninstalled: true,
            version: String::new(),
            provides: Vec::new(),
            timestamp: Some(timestamp),
        },
    );

    save_manual_state(config, state)?;
    Ok(())
}

/// Print all manually tracked packages
pub fn list_manual_state(_config: &Config, state: &ManualState) {
    if state.packages.is_empty() {
        println!("{}", tr!("no manually tracked packages"));
        return;
    }

    for (pkg, info) in &state.packages {
        let status = if info.manually_installed {
            tr!("installed")
        } else if info.manually_uninstalled {
            tr!("uninstalled")
        } else {
            tr!("unknown")
        };
        println!(
            "{} {} {} {}",
            pkg,
            info.version,
            status,
            info.timestamp.as_deref().unwrap_or("")
        );
    }
}

/// Sync manual state into an alpm handle at startup
/// manually_installed → IgnorePkg, manually_uninstalled → AssumeInstalled
pub fn sync_manual_state_to_alpm(alpm: &mut alpm::Alpm, state: &ManualState) {
    for (pkg, info) in &state.packages {
        if info.manually_installed {
            let _ = alpm.add_ignorepkg(pkg.as_str());
        }
        if info.manually_uninstalled {
            let _ = alpm.add_assume_installed(&alpm::Depend::new(pkg.as_str()));
        }
    }
}

/// Scan installed shared libraries for SONAME entries to use as provides.
/// Looks in /usr/lib/ for lib<pkg>.so* and extracts DT_SONAME via readelf.
pub fn detect_elf_provides(pkg: &str) -> Option<Vec<String>> {
    let mut provides = Vec::new();

    // Search paths for shared libraries
    for lib_dir in &["/usr/lib", "/usr/lib64"] {
        let dir = Path::new(lib_dir);
        if !dir.exists() {
            continue;
        }

        // Match lib<pkg>.so* and lib<pkg>-*.so* patterns
        let pattern = format!("lib{}", pkg);
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if !name.starts_with(&pattern) {
                    continue;
                }
                if !name.contains(".so") {
                    continue;
                }
                // Skip symlinks (only process real .so files)
                let path = entry.path();
                if path.is_symlink() {
                    continue;
                }

                // Run readelf -d to get SONAME
                if let Ok(output) = Command::new("readelf")
                    .args(["-d", &path.to_string_lossy()])
                    .output()
                {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for line in stdout.lines() {
                        if line.contains("SONAME") {
                            // Format: " 0x000000000000000e (SONAME)  Library soname: [libfoo.so.1]"
                            if let Some(start) = line.find('[') {
                                if let Some(end) = line.find(']') {
                                    let soname = &line[start + 1..end];
                                    provides.push(soname.to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Also try /usr/lib64/ prefix-less match for packages like "crypto" → libcrypto.so
    // (already covered by prefix matching above)

    if provides.is_empty() {
        None
    } else {
        provides.sort();
        provides.dedup();
        Some(provides)
    }
}
