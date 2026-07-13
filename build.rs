fn main() {
    println!("cargo:warning=build.rs: setting rpath for libalpm");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/home/Qaaxaap/local/pacman/lib");
}
