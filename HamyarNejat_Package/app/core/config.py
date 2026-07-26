"""
پیکربندی مرکزی همیار نجات
Central configuration for Hamyar Nejat.

تمام نام مدل‌ها و آدرس سرور محلی فقط در همین فایل تعریف می‌شوند.
Every model name and the local server address are defined ONLY here.

Why this file exists
--------------------
`ingest.py` embedded documents with "bge-m3" while `retrieve.py` queried with
"bge-m3:latest". Ollama normally resolves a bare name to the ":latest" tag, so
the two agree by luck rather than by design. If the shipped model is ever
tagged anything else (for example "bge-m3:567m"), the bare name resolves to a
manifest that does not exist and retrieval fails at runtime.

Worse, `retrieve_context()` swallows that exception and returns an empty
string, so the assistant answers with no grounding at all and nobody is told
the knowledge base was skipped. In an emergency-response tool that is the most
dangerous possible failure mode: confident, ungrounded answers.

Defining the names once removes the possibility of drift.
"""

import os

# -----------------------------------------------------------------------------
# Ollama endpoint
# -----------------------------------------------------------------------------
# 127.0.0.1 rather than localhost: on Windows, "localhost" can resolve to ::1
# first while Ollama is bound to IPv4, costing a failed connection attempt on
# every single call.
OLLAMA_BASE_URL = os.getenv("HAMYAR_OLLAMA_URL", "http://127.0.0.1:11434")

# -----------------------------------------------------------------------------
# Model names
# -----------------------------------------------------------------------------
# Tags are explicit. Do not rely on ":latest" resolution.
# These MUST match the manifests shipped in installers/models/manifests/ and the
# $RequiredModels list in run.ps1.
EMBED_MODEL = os.getenv("HAMYAR_EMBED_MODEL", "bge-m3:latest")
LLM_MODEL = os.getenv("HAMYAR_LLM_MODEL", "aya-expanse:8b")

# -----------------------------------------------------------------------------
# Runtime behaviour
# -----------------------------------------------------------------------------
# Keep the model resident between questions. Ollama's default is 5 minutes,
# which means a user who pauses to read an answer pays the full multi-second
# reload cost on their next question.
KEEP_ALIVE = os.getenv("HAMYAR_KEEP_ALIVE", "30m")

# Generation timeout in seconds. An 8B model on CPU-only hardware is slow;
# this needs to be generous or long answers get cut off mid-sentence.
REQUEST_TIMEOUT = int(os.getenv("HAMYAR_TIMEOUT", "600"))

# Context window passed to Ollama. Retrieved context plus history plus the
# Persian system prompt can be long; the default of 2048 silently truncates.
NUM_CTX = int(os.getenv("HAMYAR_NUM_CTX", "8192"))

# Number of knowledge-base chunks retrieved per question.
TOP_K = int(os.getenv("HAMYAR_TOP_K", "3"))

# -----------------------------------------------------------------------------
# Knowledge base
# -----------------------------------------------------------------------------
TABLE_NAME = "knowledge_base"

# Folder holding the source Markdown articles, relative to the app directory.
# `ingest.py` and `retrieve.py` previously disagreed about this too
# ("Articles" vs "knowledge-files").
ARTICLES_DIRNAME = os.getenv("HAMYAR_ARTICLES_DIR", "knowledge-files")

# UI label -> metadata value used for pre-filtering in LanceDB.
CATEGORY_MAPPING = {
    "فوریت‌های پزشکی": "medical_emergency",
    "فوریت‌های فنی": "technical_emergency",
    "فوریت‌های روانشناسی": "psychological_emergency",
    "فوریت‌های امدادی": "rescue_emergency",
}
