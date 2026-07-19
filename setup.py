import os
import subprocess
import lancedb

def check_ollama():
    try:
        # Check if Ollama is accessible
        result = subprocess.run(['ollama', '--version'], capture_output=True, text=True)
        if result.returncode == 0:
            print("Ollama is installed:", result.stdout.strip())
            return True
    except FileNotFoundError:
        pass
    print("Error: Ollama is not installed or not added to PATH. Please install Ollama for Windows.")
    return False

def pull_models():
    print("Starting model pulls in the background...")
    # Popen runs the commands in the background without blocking the script
    subprocess.Popen(['ollama', 'pull', 'aya-expanse:8b'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.Popen(['ollama', 'pull', 'bge-m3'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Models 'aya-expanse:8b' and 'bge-m3' are downloading in the background.")

def setup_lancedb():
    # Setup local LanceDB connection
    db_path = os.path.join(os.path.dirname(__file__), "lancedb_data")
    db = lancedb.connect(db_path)
    print(f"LanceDB connected successfully at {db_path}")

def main():
    print("Initializing Offline Rescue Assistant...")
    if check_ollama():
        pull_models()
    setup_lancedb()
    print("Setup complete.")

if __name__ == "__main__":
    main()
