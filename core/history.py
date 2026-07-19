import os
import json
import uuid
from datetime import datetime

HISTORY_FILE = os.path.join(os.path.dirname(os.path.dirname(__file__)), "chat_history.json")

def load_all_sessions():
    if not os.path.exists(HISTORY_FILE):
        return {}
    try:
        with open(HISTORY_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return {}

def save_all_sessions(sessions):
    with open(HISTORY_FILE, 'w', encoding='utf-8') as f:
        json.dump(sessions, f, ensure_ascii=False, indent=4)

def get_valid_sessions():
    sessions = load_all_sessions()
    valid_sessions = {}
    cleaned = False
    
    for sid, data in sessions.items():
        if len(data.get("messages", [])) > 0:
            valid_sessions[sid] = data
        else:
            cleaned = True
            
    if cleaned:
        save_all_sessions(valid_sessions)
        
    return valid_sessions

def create_new_session(title="چت جدید"):
    # Lazy Initialization: We only return the ID and don't write to disk yet
    session_id = str(uuid.uuid4())
    return session_id

def get_session_data(session_id):
    sessions = load_all_sessions()
    return sessions.get(session_id, {
        "title": "چت جدید",
        "messages": [],
        "timestamp": datetime.now().isoformat()
    })

def add_message_to_session(session_id, role, content, title="چت جدید"):
    sessions = load_all_sessions()
    if session_id not in sessions:
        sessions[session_id] = {
            "title": title,
            "messages": [],
            "timestamp": datetime.now().isoformat()
        }
    sessions[session_id]["messages"].append({"role": role, "content": content})
    
    # Only save to disk if there is at least one message
    if len(sessions[session_id]["messages"]) > 0:
        save_all_sessions(sessions)

def delete_session(session_id):
    sessions = load_all_sessions()
    if session_id in sessions:
        del sessions[session_id]
        save_all_sessions(sessions)
