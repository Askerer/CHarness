# Codex Agent Harness (Docker Sandbox Edition)

本倉庫為精簡後的 **Codex Agent Harness**，移除了所有終端機互動介面（TUI）、桌面端包裝器、語音模組、外部語言 SDK 與 Monorepo 發佈腳本，僅保留**無頭（Headless）Agent 控制迴圈、工具系統、沙盒隔離層與 JSON-RPC / JSONL 通訊介面**，專為在 Docker Sandbox 中部署與調用而設計。

詳細的模組保留依據與七層架構解析請參閱：
- **[`HARNESS_ARCHITECTURE.md`](./HARNESS_ARCHITECTURE.md)** — 完整說明為什麼留下的每個 Crate 屬於 Agent Harness、被剔除的模組為何，以及三種 Docker Sandbox 調用架構。

---

## 目錄結構

```text
.
├── Dockerfile                  # 多階段建置：編譯 Rust Harness 執行檔並封裝為 Ubuntu 24.04 Sandbox Image
├── docker-compose.yml          # 支援 app-server (WebSocket)、codex-exec (CLI/JSONL) 與 exec-server 三種服務模式
├── docker/
│   ├── codex                   # 容器內統一無頭 CLI 入口 (轉發 exec / app-server / exec-server)
│   ├── entrypoint.sh           # 容器啟動入口：支援 HARNESS_MODE 切換與可選防火牆初始化
│   ├── init_firewall.sh        # 容器內 iptables + ipset 網域白名單防火牆腳本
│   └── run_in_sandbox.sh       # 宿主機一鍵啟動 Docker Sandbox 輔助腳本
├── HARNESS_ARCHITECTURE.md     # Harness 架構分層與模組保留原因說明文件
└── codex-rs/                   # Codex Agent Harness 核心 Rust Workspace
    ├── core/                   # Agent 控制迴圈、Turn 狀態機、Session、Compaction、Subagents
    ├── exec/                   # 非互動式 CLI 與 JSONL 事件串流入口 (`codex-exec`)
    ├── app-server/             # 雙向 JSON-RPC 2.0 伺服器入口 (`codex-app-server` & `exec-server`)
    ├── exec-server/            # PTY 子程序池與沙盒檔案系統 JSON-RPC 執行器
    ├── tools/                  # 工具註冊表、Schema 生成與內建工具處置器
    ├── apply-patch/            # 模型專用補丁解析與套用工具 (`apply_patch`)
    ├── code-mode*/             # V8 隔離式 JavaScript 工具編排執行期
    ├── sandboxing/             # 跨平台沙盒策略轉換器
    ├── linux-sandbox/          # Linux Landlock + Seccomp + Bubblewrap 沙盒執行器
    ├── bwrap/                  # 內嵌 Bubblewrap 建置封裝
    ├── execpolicy/             # Starlark 命令執行安全策略引擎
    ├── network-proxy/          # 沙盒零信任網路代理與網域白名單過濾
    ├── responses-api-proxy/    # API Key 憑證隔離代理
    ├── codex-mcp/              # Model Context Protocol (MCP) 整合層
    ├── prompts/                # 系統提示詞與權限模板
    ├── protocol/               # 核心資料協定與 Harness Metadata 定義
    └── ...                     # 記憶、Hooks、Skills、State DB、Auth 與底層工具庫
```

---

## 快速開始（Docker Sandbox）

### 1. 建置映像檔

```bash
docker build -t codex-harness:latest .
```

### 2. 單次任務／JSONL 事件串流調用（`codex-exec`）

```bash
docker run --rm -i \
  --security-opt seccomp=unconfined \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  -v "$(pwd):/workspace" \
  -w /workspace \
  codex-harness:latest \
  exec --json --full-auto --skip-git-repo-check "分析此專案並執行測試"
```

### 3. 常駐雙向 JSON-RPC 伺服器調用（`codex-app-server`）

```bash
OPENAI_API_KEY="$OPENAI_API_KEY" WORKSPACE_DIR="$(pwd)" \
  docker compose up -d codex-app-server
```

連線至 `ws://localhost:8080` 即可透過 JSON-RPC 2.0 控制多輪對話、接收串流輸出與管理審批。

---

## 授權

本專案採用 [Apache-2.0 License](./LICENSE) 授權。
