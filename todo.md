# Writing the Graphical Installer PowerShell Script

**Task Description:**
Writing the core part of the project: a PowerShell script that displays a beautiful graphical user interface using the Windows Forms tool, shows all installation steps to the user with a progress bar, and provides clear and guiding Persian messages at each step. This task is the heart of the installation user experience.

## 1- Designing the Graphical Interface
*   Mental design of the installation window: Title, logo, progress bar, status text, buttons.
*   Decision on window size (Recommendation: 600x400 pixels).
*   Selecting colors aligned with the Hamyar Nejat brand (Red, White, Dark).
*   Designing different window states: Start, Working, Error, Success.

## 2- Writing the Base GUI Code
*   Create the `install.ps1` file.
*   Load Windows Forms assemblies.
*   Create the main window with appropriate settings.
*   Add titles, logo, and text labels.
*   Add a progress bar and status message box.
*   Configure colors and fonts (Persian font).

## 3- Writing the System Check Logic
*   Function to check Admin status (If not, request Elevation).
*   Function to check the Windows version.
*   Function to check available RAM.
*   Function to check free disk space.
*   Function to check the installation path (Absence of Persian characters).
*   Display results in the window.

## 4- Writing the Python Installation Logic
*   Check if Python is installed or not.
*   If not: Execute the `python-installer` file with silent parameters.
*   Automatically add Python to the system PATH.
*   Check installation success.
*   Update the progress bar (0% to 25%).
*   Handle errors with Persian messages.

## 5- Writing the Libraries Installation Logic
*   Set the pip path.
*   Execute the installation command from the `libraries` folder offline.
*   Use `pip install --no-index --find-links=libraries -r requirements.txt`.
*   Update the progress bar (25% to 50%).
*   Display the name of the library currently being installed.

## 6- Writing the Ollama Installation and Model Copying Logic
*   Check if Ollama is installed or not.
*   Execute `OllamaSetup.exe` silently.
*   Copy the model folder to the Ollama models path.
*   Check success.
*   Update the progress bar (50% to 90%).

## 7- Creating Shortcuts and Finalization
*   Create a shortcut on the user's Desktop.
*   Create a shortcut in the Start Menu.
*   Set icons for the shortcuts.
*   Display the final success message.
*   Update the progress bar (90% to 100%).