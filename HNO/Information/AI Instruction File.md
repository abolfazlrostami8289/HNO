# AI Instruction File

## Project Goals
This product is a completely offline AI assistant designed for crisis situations where internet and communication networks are unavailable. Its primary purpose is to provide emergency information and step-by-step guidance across four critical domains: Medical, Psychiatric, Technical, and Relief/Rescue.

## Tech Stack
- **Core Languages & Distribution:**
  - **PowerShell (~54.5%):** Primary language for installers, system automation, service/process management, and Windows component interaction.
  - **Python (~43.3%):** Used for the backend, processing logic, and flexible libraries.
  - **Batchfile (~1.2%):** Used for quick system commands and startup/launcher scripts.
- **Frontend:** Streamlit (used as a lightweight GUI).
- **LLM Management:** Ollama is used to manage local language models.
- **Knowledge Base:** Markdown (.md) files are used for the offline knowledge base.
- **Dependencies:** Python libraries are strictly managed via the "requirements.txt" file in the root directory.
- **Tools:** Git and GitHub for version control and collaboration.
- **Target OS:** Strictly Windows 10 and Windows 11 (due to the heavy reliance on PowerShell and Windows offline environments).

## Project Architecture & Directory Structure
- **`HNO\` (Root Repository)**
  - **`HNO\Articles\`**: Contains the offline article files that the product displays to the user.
  - **`HNO\logs\`**: Stores log files that track events, errors, and successes during the installation and uninstallation processes.
  - **`install.ps1`**: The main PowerShell script responsible for installing the application.
  - **`run.ps1`**: The main PowerShell script responsible for executing/running the application.

- **`HNO\HamyarNejat_Package\` (Main Application Package)**
  - **`app\`**: The frontend directory.
    - `app.py`: The main Streamlit entry point. It acts as the landing page and provides navigation to the Chat and Article sections.
    - **`assets\`**:
      - `Vazirmatn-Regular.woff2`: The primary font file used in the application.
    - **`pages\`**:
      - `1_Chat.py`: The offline AI chat interface.
      - `2_Article.py`: The interface for browsing and reading offline articles.
  - **`libraries\`**: Contains all the required Python libraries for offline usage.

- **`HNO\HamyarNejat_Package\installers\` (CRITICAL: Installation Files & Binaries)**
  *Note: Paths in this directory must not be altered, as they are crucial for the offline, portable deployment.*
  - **`python\`**: Contains the extracted files from `python-3.13.12-embed-amd64.zip` (downloaded from the official Python website) for the embedded Python environment.
  - **`ollama_portable\`**: Contains the portable version of Ollama, extracted from `ollama-windows-amd64.zip`. This specific version is used to minimize installation risks on host machines.
  - **`models\manifests\registry.ollama.ai\library\`**: Contains the specific language models used by the app. It must include the folders for the `bge-m3` and `aya-expanse` models.
  - `logo.ico`: The icon file used when creating the application shortcut for the user.

## Constraints & Safety Guidelines

### Golden Rules & Constraints

1. **Path Integrity (CRITICAL)**:
   - Always refer back to this `AI Instruction File.md` to verify directory and file structures BEFORE writing or modifying any file paths in scripts.
   - Never assume, hardcode absolute paths (like `C:\Users\...`), or alter the relative folder structure of the `installers` directory (Python embed, Ollama portable, models, logo, etc.).

2. **Error Handling & Log Inspection**:
   - In the event of any runtime, installation, or execution errors, ALWAYS check the log files located in `HNO\logs\` first to diagnose the root cause.
   - Do not guess solutions or rewrite large blocks of code without referencing the logs and pinpointing the exact failure point.

3. **Strict Offline First Principle**:
   - Never write code, scripts, or dependencies that require an active internet connection at runtime or during installation.
   - All Python packages, binaries, fonts, and model files must be sourced exclusively from local paths within the repository (e.g., `HNO\HamyarNejat_Package\libraries` and `HNO\HamyarNejat_Package\installers`).

4. **Low-Risk Decision Making**:
   - Favor minimal, modular, and non-destructive code changes over refactoring working components.
   - Preserve existing system configurations and registry settings unless explicitly required by the task.
   - Maintain strict PowerShell (Windows 10/11) and Python embedded environment compatibility.

5. **Dependency Boundary**:
   - Do not add new external libraries or dependencies without explicit instruction. Rely solely on what is already available in `requirements.txt` or pre-packaged within the repository.
