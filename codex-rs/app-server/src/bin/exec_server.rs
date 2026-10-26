//! Standalone `exec-server` binary entrypoint.
//!
//! Supports `--listen ws://IP:PORT` (defaults to `ws://127.0.0.1:0`) and
//! `--listen stdio://`, while also handling the hidden helper argv modes
//! (`--codex-run-as-arg0-exec-helper` and `--codex-run-as-fs-helper`) when
//! `exec-server` re-execs `codex_self_exe` for sandboxed operations.

use clap::Parser;
use codex_exec_server::DEFAULT_LISTEN_URL;
use codex_exec_server::ExecServerRuntimeOptions;
use codex_http_client::HttpClientFactory;
use codex_http_client::OutboundProxyPolicy;
use std::ffi::OsStr;

const CODEX_LINUX_SANDBOX_EXE_ENV_VAR: &str = "CODEX_TEST_LINUX_SANDBOX_EXE";

#[derive(Debug, Parser)]
struct ExecServerArgs {
    /// Transport endpoint URL (`ws://IP:PORT`, `stdio`, or `stdio://`).
    #[arg(long = "listen", value_name = "URL", default_value = DEFAULT_LISTEN_URL)]
    listen: String,
}

fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    #[cfg(target_os = "linux")]
    codex_utils_pty::init_spawn_helper(std::env::args_os());
    let mut args = std::env::args_os();
    let _ = args.next();
    let argv1 = args.next();
    #[cfg(unix)]
    if argv1.as_deref() == Some(OsStr::new(codex_exec_server::CODEX_ARG0_EXEC_HELPER_ARG1)) {
        codex_exec_server::run_arg0_exec_helper_main();
    }
    if argv1.as_deref() == Some(OsStr::new(codex_exec_server::CODEX_FS_HELPER_ARG1)) {
        codex_exec_server::run_fs_helper_main();
    }

    let cli = ExecServerArgs::parse();
    let current_exe = std::env::current_exe()?;
    let codex_linux_sandbox_exe =
        std::env::var_os(CODEX_LINUX_SANDBOX_EXE_ENV_VAR).map(std::path::PathBuf::from);
    let runtime_paths = ExecServerRuntimeOptions::new(current_exe, codex_linux_sandbox_exe)?;
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(codex_exec_server::run_main(
            &cli.listen,
            runtime_paths,
            HttpClientFactory::new(OutboundProxyPolicy::ReqwestDefault),
        ))
}
