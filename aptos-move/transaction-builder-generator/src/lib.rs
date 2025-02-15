// Copyright (c) Aptos
// SPDX-License-Identifier: Apache-2.0

use aptos_types::transaction::ScriptABI;
use std::{ffi::OsStr, fs, io::Read, path::Path};

/// Support for code-generation in Rust.
pub mod rust;

/// Internals shared between languages.
mod common;

fn get_abi_paths(dir: &Path) -> std::io::Result<Vec<String>> {
    let mut abi_paths = Vec::new();
    if dir.is_dir() {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                abi_paths.append(&mut get_abi_paths(&path)?);
            } else if let Some("abi") = path.extension().and_then(OsStr::to_str) {
                // not read Genesis abi (script builder doesn't work with the script function there)
                if !path
                    .to_str()
                    .map(|s| {
                        s.contains("/Genesis/")
                            || s.contains("/Coin/")
                            || s.contains("/ManagedCoin/")
                    })
                    .unwrap()
                {
                    abi_paths.push(path.to_str().unwrap().to_string());
                }
            }
        }
    }
    Ok(abi_paths)
}

/// Read all ABI files the specified directories. This supports both new and old `ScriptABI`s.
pub fn read_abis(dir_paths: &[impl AsRef<Path>]) -> anyhow::Result<Vec<ScriptABI>> {
    let mut abis = Vec::<ScriptABI>::new();
    for dir in dir_paths.iter() {
        for path in get_abi_paths(dir.as_ref())? {
            let mut buffer = Vec::new();
            let mut f = std::fs::File::open(path)?;
            f.read_to_end(&mut buffer)?;
            abis.push(bcs::from_bytes(&buffer)?);
        }
    }
    // Sort scripts by alphabetical order.
    #[allow(clippy::unnecessary_sort_by)]
    abis.sort_by(|a, b| {
        let a0 = if let ScriptABI::ScriptFunction(sf) = a {
            sf.module_name().name().to_string()
        } else {
            "".to_owned()
        };
        let b0 = if let ScriptABI::ScriptFunction(sf) = b {
            sf.module_name().name().to_string()
        } else {
            "".to_owned()
        };
        (a0, a.name()).cmp(&(b0, b.name()))
    });
    Ok(abis)
}

/// How to copy ABI-generated source code for a given language.
pub trait SourceInstaller {
    type Error;

    /// Create a module exposing the transaction builders for the given ABIs.
    fn install_transaction_builders(
        &self,
        name: &str,
        abis: &[ScriptABI],
    ) -> std::result::Result<(), Self::Error>;
}
