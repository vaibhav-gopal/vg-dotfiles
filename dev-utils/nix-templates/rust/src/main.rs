//! A starter binary: prints a greeting. Rename the package in Cargo.toml (and Cargo.lock).

/// The greeting for `name`.
fn greeting(name: &str) -> String {
    format!("Hello, {name}!")
}

fn main() {
    println!("{}", greeting("world"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greets_by_name() {
        assert_eq!(greeting("nix"), "Hello, nix!");
    }
}
