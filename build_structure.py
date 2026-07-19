import os
import shutil

def create_structure():
    base_dir = "HamyarNejat_Package"
    
    # Task 1-1: Create folders
    subfolders = ["installers", "app", "knowledge", "branding", "libraries", "docs"]
    
    os.makedirs(base_dir, exist_ok=True)
    for folder in subfolders:
        os.makedirs(os.path.join(base_dir, folder), exist_ok=True)
        
    print("Folders created successfully.")

    # Task 1-2: Create versions.txt
    versions_content = """=== اطلاعات نسخه‌های پکیج همیار نجات ===
Python Version: 
Ollama Version: 
LLM Model Name & Size: 
Total Package Size: 
Date Packaged: 
"""
    versions_path = os.path.join(base_dir, "versions.txt")
    with open(versions_path, "w", encoding="utf-8") as f:
        f.write(versions_content)
        
    print("versions.txt created successfully.")

    # Task 1-3: Copy source codes to app
    app_dir = os.path.join(base_dir, "app")
    
    # Items to copy
    items_to_copy = ["app.py", "core", "pages"]
    
    for item in items_to_copy:
        if os.path.exists(item):
            dest_path = os.path.join(app_dir, item)
            if os.path.isdir(item):
                if os.path.exists(dest_path):
                    shutil.rmtree(dest_path)
                shutil.copytree(item, dest_path)
            else:
                shutil.copy2(item, dest_path)
            print(f"Copied {item} to {app_dir}")
        else:
            print(f"Warning: {item} does not exist in the current directory.")

if __name__ == "__main__":
    create_structure()
    print("Package structure built successfully!")
