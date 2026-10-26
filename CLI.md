  已完成 Repo 精簡與 Docker Sandbox 封裝，只保留完整的無頭（Headless）Codex Agent Harness 核心閉包，並撰寫了架構與模組保留說明文件。

  ### 1. 架構說明與保留依據文件

  • **HARNESS_ARCHITECTURE.md**：完整說明 Codex 原始碼中 Harness 的定義（如
  ContentItemProvenance::Harness、CodexHarnessMetadata、TurnToolSource::Harness），並將保留在 Cargo.toml 的模組拆解為七大架構層次：
      1. 無頭調用入口層：codex-exec（CLI / JSONL 事件流）、codex-app-server（雙向 JSON-RPC 2.0
      Server：stdio://、ws://、unix://）、arg0（單一執行檔多模態分發器）。
      2. Agent 核心控制迴圈與狀態層：core（CodexThread、ThreadManager、Turn 狀態機、Compaction、Subagent
      調度）、protocol、state、rollout、history、config。
      3. 提示詞組裝、上下文工程與記憶層：prompts、context-fragments、skills、hooks、memories/read、memories/write、agent-graph-store、message-board。   
      4. 工具系統、Code Mode 與擴充插件層：tools、apply-patch、shell-command（Tree-sitter AST 命令解析）、code-mode*（V8 隔離執行期）、codex-
      mcp、ext/*（guardian-reviewer、guardian-v2、goal 等）。
      5. 沙盒隔離與環境執行層：exec-server（PTY 與檔案系統 RPC 執行器）、sandboxing、linux-sandbox、bwrap、execpolicy（Starlark 策略引擎）、network-    
      proxy、responses-api-proxy。
      6. 模型通訊與認證層：codex-api、codex-client、models-manager、login、agent-identity、workload-identity。
      7. 可觀測性與底層工具庫：otel、utils/pty、utils/output-truncation 等。
  • 已剔除的非 Harness 元件：
      • 根目錄非 Harness 區塊：sdk/、codex-cli/、bazel/、third_party/、patches/、tools/、scripts/、docs/、.github/ 及所有 BUILD.bazel。
      • codex-rs/ 內非 Harness Crates（共 28 個）：tui、cli、ansi-escape、mermaid、message-history、cloud-client、cloud-tasks*、voice-host、realtime-   
      webrtc、v8-poc、thread-manager-sample、app-server-test-client、config-schema、core-api、direct-tool-timing、ext/guardian-v3、runtime-agent-       
      instance、stdio-to-uds、tcp-tunnel、windows-sandbox-service、utils/approval-presets、utils/critical-path、utils/elapsed、utils/fuzzy-
      match、utils/readiness、utils/sleep-inhibitor。
  ──────
  ### 2. Docker Sandbox 建置與調用配置
  新增與調整的檔案：

  • **Dockerfile**：多階段建置 codex-exec、codex-app-server、exec-server、codex-linux-sandbox、bwrap、apply_patch、codex-execpolicy、codex-code-mode-   
  ￺host、codex-responses-api-proxy，封裝至 Ubuntu 24.04 非 root（codex）沙盒環境。
  • **docker-compose.yml**：提供 codex-app-server（WebSocket 8080）、codex-exec（JSONL CLI）與 codex-exec-server（Port 31987）三種啟動 Profile。        
  • **entrypoint.sh**、**codex**、**init_firewall.sh**、**run_in_sandbox.sh**：支援 HARNESS_MODE（exec | app-server | exec-server）與
  ENABLE_FIREWALL=1（iptables + ipset 網域白名單隔離）。
  • **exec_server.rs**：擴充獨立 exec-server binary 支援 --listen <URL> 參數。

  #### 常用調用指令

    # 1. 建置 Docker Sandbox Image
    docker build -t codex-harness:latest .

    # 2. 模式一：單次任務 / JSONL 串流輸出 (codex-exec)
    docker run --rm -i \
      --security-opt seccomp=unconfined \
      -e OPENAI_API_KEY="$OPENAI_API_KEY" \
      -v "$(pwd):/workspace" \
      -w /workspace \
      codex-harness:latest \
      exec --json --full-auto --skip-git-repo-check "檢查專案並執行測試"

    # 3. 模式二：常駐雙向 JSON-RPC 2.0 Server (codex-app-server，監聽 ws://localhost:8080)
    OPENAI_API_KEY="$OPENAI_API_KEY" WORKSPACE_DIR="$(pwd)" \
      docker compose up -d codex-app-server