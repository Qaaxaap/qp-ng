use crate::config::Config;

use std::fs;
use std::io::Write;
use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use tr::tr;

/// Create a fake pacman local DB entry under /var/lib/pacman/local/<name>-<version>/
/// Writes standard pacman `desc` and `files` files so dependency resolution works.
pub fn create_fake_local_db_entry(
    config: &Config,
    name: &str,
    version: &str,
    provides: &[String],
    depends: &[String],
    reason: u32,
    size: i64,
    files: &[String],
) -> Result<()> {
    let dbpath = PathBuf::from(config.alpm.dbpath()).join("local");
    let pkg_dir = dbpath.join(format!("{}-{}", name, version));

    if pkg_dir.exists() {
        bail!(tr!("package entry already exists: {}", pkg_dir.display()));
    }

    fs::create_dir_all(&pkg_dir)
        .with_context(|| tr!("failed to create package directory: {}", pkg_dir.display()))?;

    // Build desc file in pacman DB format
    let mut desc = String::new();
    desc.push_str(&format!("%NAME%\n{}\n\n", name));
    desc.push_str(&format!("%VERSION%\n{}\n\n", version));
    desc.push_str(&format!("%REASON%\n{}\n\n", reason));
    desc.push_str(&format!("%SIZE%\n{}\n\n", size));
    desc.push_str("%VALIDATED%\nNone\n\n");

    for dep in depends {
        desc.push_str(&format!("%DEPENDS%\n{}\n\n", dep));
    }
    for prov in provides {
        desc.push_str(&format!("%PROVIDES%\n{}\n\n", prov));
    }

    desc.push_str("%FILES%\nfiles\n\n");

    let desc_path = pkg_dir.join("desc");
    let mut f = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&desc_path)
        .with_context(|| tr!("failed to create desc file: {}", desc_path.display()))?;
    f.write_all(desc.as_bytes())
        .with_context(|| tr!("failed to write desc file: {}", desc_path.display()))?;

    // Build files file
    let mut files_content = String::from("%FILES%\n");
    for file in files {
        files_content.push_str(file);
        files_content.push('\n');
    }

    let files_path = pkg_dir.join("files");
    let mut f = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&files_path)
        .with_context(|| tr!("failed to create files file: {}", files_path.display()))?;
    f.write_all(files_content.as_bytes())
        .with_context(|| tr!("failed to write files file: {}", files_path.display()))?;

    Ok(())
}

/// Remove a pacman local DB entry directory
pub fn remove_local_db_entry(config: &Config, name: &str, version: &str) -> Result<()> {
    let dbpath = PathBuf::from(config.alpm.dbpath()).join("local");
    let pkg_dir = dbpath.join(format!("{}-{}", name, version));

    if !pkg_dir.exists() {
        bail!(tr!("package entry does not exist: {}", pkg_dir.display()));
    }

    fs::remove_dir_all(&pkg_dir)
        .with_context(|| tr!("failed to remove package directory: {}", pkg_dir.display()))?;

    Ok(())
}

/// Find all (name, version) entries in the local DB matching a package name
pub fn find_local_db_entries(config: &Config, name: &str) -> Result<Vec<(String, String)>> {
    let dbpath = PathBuf::from(config.alpm.dbpath()).join("local");
    let mut entries = Vec::new();

    if !dbpath.exists() {
        return Ok(entries);
    }

    for entry in fs::read_dir(&dbpath)
        .with_context(|| tr!("failed to read local db directory: {}", dbpath.display()))?
    {
        let entry = entry?;
        let dir_name = entry.file_name().to_string_lossy().to_string();
        // pacman DB directories use the format <name>-<version>
        if let Some(pos) = dir_name.rfind('-') {
            let pkg_name = &dir_name[..pos];
            let pkg_version = &dir_name[pos + 1..];
            if pkg_name == name && pkg_version.chars().any(|c| c.is_numeric()) {
                entries.push((pkg_name.to_string(), pkg_version.to_string()));
            }
        }
    }

    Ok(entries)
}
