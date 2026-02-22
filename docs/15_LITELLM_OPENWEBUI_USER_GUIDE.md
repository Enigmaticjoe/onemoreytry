# 15 — LiteLLM + Open WebUI: Setup and User Guide

**Who this guide is for:** You've got your home AI stack running and now you want to actually *use* it. This guide explains what LiteLLM and Open WebUI are (in plain English), how to connect them together, and how to get the most out of them — including cloud AI providers, document chat, image analysis, and advanced features.

---

## Table of Contents

1. [What Is LiteLLM? (Plain English)](#1-what-is-litellm-plain-english)
2. [What Is Open WebUI? (Plain English)](#2-what-is-open-webui-plain-english)
3. [How They Work Together](#3-how-they-work-together)
4. [Connecting Open WebUI to LiteLLM](#4-connecting-open-webui-to-litellm)
5. [Connecting Open WebUI to OpenClaw](#5-connecting-open-webui-to-openclaw)
6. [Adding Cloud AI Providers to LiteLLM](#6-adding-cloud-ai-providers-to-litellm)
7. [Master Prompts and System Prompts](#7-master-prompts-and-system-prompts)
8. [Model Selection Guide: When to Use Which Model](#8-model-selection-guide)
9. [Creating Custom Model Presets in Open WebUI](#9-creating-custom-model-presets)
10. [Using RAG — Chat with Your Documents](#10-using-rag--chat-with-your-documents)
11. [Image Analysis with intel-vision (llava)](#11-image-analysis-with-intel-vision)
12. [Pipelines and Tools (Function Calling, Web Search)](#12-pipelines-and-tools)
13. [Knowledge Bases in Open WebUI](#13-knowledge-bases-in-open-webui)
14. [Tips and Tricks for 2026](#14-tips-and-tricks-for-2026)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. What Is LiteLLM? (Plain English)

Imagine you have ten different TV remotes — one for your TV, one for your soundbar, one for your streaming box, one for your DVD player. LiteLLM is like a **universal remote** that controls all of them with one button layout.

In AI terms: there are many different AI providers (OpenAI, Anthropic, Google, local Ollama models, etc.) and they all speak slightly different "languages" in terms of how you send them requests. **LiteLLM acts as a universal translator.** You send one type of request, and LiteLLM figures out how to talk to whichever AI you're pointing at.

**What it does for your home lab:**
- Sits at `http://192.168.1.222:4000` and accepts AI chat requests
- Routes those requests to the right AI: local vLLM on Node A, Ollama on Node C, or cloud APIs like OpenAI
- Lets you use a single API key (`sk-master-key`) for everything, hiding the complexity underneath
- Gives you a dashboard to manage models, track usage, and control access
- Lets you set up "aliases" like `brain-heavy` or `brawn-fast` instead of memorizing model names

**Think of it this way:** Without LiteLLM, every app (Home Assistant, Open WebUI, your scripts) would need to know about every AI provider separately. With LiteLLM, they all just talk to one place, and LiteLLM handles the rest.

---

## 2. What Is Open WebUI? (Plain English)

Open WebUI is your **personal, private version of ChatGPT** — running entirely on your own hardware, with no data leaving your home unless you choose to connect to cloud services.

It's a chat interface you open in your web browser. You type a message, the AI responds. But it has many extra features beyond basic chat:

- Upload and chat with PDF documents
- Attach and analyze images
- Save and organize conversations
- Switch between multiple AI models in the same conversation
- Create custom AI "personas" with different personalities and specialties
- Share conversations with others on your network
- Use it as an API endpoint for other apps

**Where it lives:** `http://192.168.1.6:3000`

**Who runs it:** It runs in Docker on Node C (your Intel Arc machine), under the container name `chimera_face`.

Open WebUI connects to LiteLLM (and optionally OpenClaw) to get its AI powers. Open WebUI is the *face* — the thing you look at and type into. LiteLLM is the *engine* underneath.

---

## 3. How They Work Together

Here's the flow of a message from your fingers to an AI response:

```
You type a message in Open WebUI (http://192.168.1.6:3000)
         │
         ▼
Open WebUI sends it to LiteLLM (http://192.168.1.222:4000/v1)
         │
         ▼
LiteLLM looks at which model you chose and routes accordingly:
  ├─ brain-heavy → Node A vLLM (http://192.168.1.9:8000)
  ├─ brawn-fast  → Node B vLLM (http://192.168.1.222:8002)
  └─ intel-vision → Node C Ollama/llava (http://192.168.1.6:11434)
         │
         ▼
The AI generates a response
         │
         ▼
Response travels back through LiteLLM → Open WebUI → your screen
```

The whole thing usually takes a few seconds to under a minute depending on which model and how complex your question is.

---

## 4. Connecting Open WebUI to LiteLLM

This is the most important connection to set up. Do this first.

### Step-by-Step Instructions

1. Open your browser and go to: `http://192.168.1.6:3000`
2. Log in (your first-ever signup creates an admin account)
3. Click your **profile picture or icon** in the bottom-left corner
4. Click **Settings**
5. Click the **Connections** tab (or look for "OpenAI API" in the settings list)
6. You'll see a section labeled **OpenAI API** or **API Connections**
7. Fill in these fields:

   | Field | Value |
   |---|---|
   | **API Base URL** | `http://192.168.1.222:4000/v1` |
   | **API Key** | `sk-master-key` |

8. Click **Verify Connection** (or the checkmark button)
9. You should see a green checkmark or a message saying "Connected successfully"
10. Click **Save**

### What If Verify Connection Fails?

- Double-check the URL: it must end in `/v1` — not just `:4000`
- Make sure LiteLLM is running: visit `http://192.168.1.222:4000/health` in your browser
- Check that you're on the same home network as Node B
- Make sure there's no typo in `sk-master-key` (no spaces, no quotes)

### Checking That Models Appear

After connecting, go back to the main chat screen. Click the **model dropdown** at the top of the chat window. You should now see a list of models including `brain-heavy`, `brawn-fast`, and any others configured in LiteLLM's `config.yaml`.

---

## 5. Connecting Open WebUI to OpenClaw

OpenClaw is an additional AI gateway running on Node C. It can give you access to extra models or act as a backup routing layer.

### Step-by-Step Instructions

1. In Open WebUI, go to **Settings → Connections**
2. Look for an option to **Add Connection** or a second API slot
3. Add a new connection with these details:

   | Field | Value |
   |---|---|
   | **API Base URL** | `http://192.168.1.6:18789/v1` |
   | **API Key** | Your `OPENCLAW_GATEWAY_TOKEN` value |

4. The `OPENCLAW_GATEWAY_TOKEN` is the token you set when deploying OpenClaw. Check your `.env` file in the OpenClaw folder if you don't remember it.
5. Click **Verify Connection**, then **Save**

Once connected, any models that OpenClaw exposes will appear alongside your LiteLLM models in the model selector.

---

## 6. Adding Cloud AI Providers to LiteLLM

Your local AI is great for privacy, but sometimes you might want access to cloud models like GPT-4, Claude, or Gemini — or use them as a fallback when your local hardware is busy. LiteLLM makes this easy.

### Where to Edit: LiteLLM's `config.yaml`

This file lives on Node B (Unraid) in the LiteLLM deployment folder. The typical path is:

```
/mnt/user/appdata/litellm/config.yaml
```

Or wherever you mapped the config volume in `litellm-stack.yml`.

### How the Config File Works

Each model you add gets a section under `model_list`. Here's the basic structure:

```yaml
model_list:
  - model_name: brain-heavy        # The alias you use in Open WebUI
    litellm_params:
      model: openai/your-model     # The real model name LiteLLM uses internally
      api_base: http://192.168.1.9:8000/v1
      api_key: "none"

  - model_name: brawn-fast
    litellm_params:
      model: openai/your-model
      api_base: http://192.168.1.222:8002/v1
      api_key: "none"
```

### Adding OpenAI (ChatGPT / GPT-4)

1. Sign up at [platform.openai.com](https://platform.openai.com) and get an API key (starts with `sk-...`)
2. Add this to your `config.yaml`:

```yaml
  - model_name: gpt-4o
    litellm_params:
      model: gpt-4o
      api_key: "sk-your-openai-api-key-here"

  - model_name: gpt-4o-mini
    litellm_params:
      model: gpt-4o-mini
      api_key: "sk-your-openai-api-key-here"
```

3. Save the file and restart LiteLLM:
   ```bash
   docker compose -f litellm-stack.yml restart
   ```

---

### Adding Anthropic Claude

1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. Add to `config.yaml`:

```yaml
  - model_name: claude-sonnet
    litellm_params:
      model: anthropic/claude-sonnet-4-5
      api_key: "sk-ant-your-anthropic-key-here"

  - model_name: claude-haiku
    litellm_params:
      model: anthropic/claude-haiku-3-5
      api_key: "sk-ant-your-anthropic-key-here"
```

---

### Adding Google Gemini

1. Get an API key from [aistudio.google.com](https://aistudio.google.com)
2. Add to `config.yaml`:

```yaml
  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-1.5-pro
      api_key: "your-google-ai-api-key-here"

  - model_name: gemini-flash
    litellm_params:
      model: gemini/gemini-1.5-flash
      api_key: "your-google-ai-api-key-here"
```

---

### Adding Mistral AI

1. Get an API key from [console.mistral.ai](https://console.mistral.ai)
2. Add to `config.yaml`:

```yaml
  - model_name: mistral-large
    litellm_params:
      model: mistral/mistral-large-latest
      api_key: "your-mistral-api-key-here"

  - model_name: mistral-small
    litellm_params:
      model: mistral/mistral-small-latest
      api_key: "your-mistral-api-key-here"
```

---

### Adding OpenRouter (Access to Hundreds of Models)

OpenRouter is like a "model store" — one API key gives you access to many models from many providers.

1. Sign up at [openrouter.ai](https://openrouter.ai) and get an API key (starts with `sk-or-...`)
2. Add to `config.yaml`:

```yaml
  - model_name: openrouter-claude
    litellm_params:
      model: openrouter/anthropic/claude-sonnet-4-5
      api_key: "sk-or-your-openrouter-key-here"

  - model_name: openrouter-llama
    litellm_params:
      model: openrouter/meta-llama/llama-3.1-70b-instruct
      api_key: "sk-or-your-openrouter-key-here"
```

---

### After Editing config.yaml

Always restart LiteLLM after any change:

```bash
cd /path/to/litellm
docker compose -f litellm-stack.yml restart
```

Then refresh Open WebUI and check the model dropdown — your new models should appear.

> **Security note:** Never commit API keys directly into config files that are shared or version-controlled. Use environment variables instead, and reference them in config.yaml with `os.environ/YOUR_KEY_NAME` syntax if LiteLLM supports it.

---

## 7. Master Prompts and System Prompts

### What Is a System Prompt?

A system prompt is a secret message you give to the AI *before* your conversation starts. It sets the rules:
- What personality should the AI have?
- What topics should it focus on?
- What should it avoid?
- How long or short should responses be?

The AI always "remembers" the system prompt even as the conversation continues.

### Where to Set a System Prompt in Open WebUI

**Option A — Global system prompt (applies to all chats):**
1. Click your profile icon → **Settings** → **General**
2. Find the **System Prompt** text box
3. Type or paste your prompt
4. Click **Save**

**Option B — Per-model system prompt (in a custom model preset):**
1. Go to **Workspace** → **Models**
2. Click **+ New Model** or edit an existing one
3. Fill in the **System Prompt** field for that specific model
4. Save the model preset

**Option C — Per-conversation system prompt:**
1. Start a new chat
2. Click the **settings/sliders icon** near the message input
3. Look for a **System Prompt** override field
4. Type your prompt for just this conversation

---

### 5 Example System Prompts

**1. General Assistant (friendly everyday helper)**
```
You are a helpful, friendly assistant. You give clear and concise answers.
You use simple language and avoid unnecessary jargon. When you're uncertain
about something, you say so. You keep responses to the point unless the user
asks for more detail.
```

**2. Home Lab Assistant (self-hosted tech expert)**
```
You are an expert assistant specializing in self-hosted software, Docker,
Linux system administration, home networking, and AI infrastructure.
You help the user manage their home lab running on multiple nodes including
Unraid, Docker containers, Ollama, LiteLLM, and Home Assistant.
When providing commands, make them copy-paste ready.
Assume the user has basic technical knowledge but explain advanced concepts.
```

**3. Code Helper (programming assistant)**
```
You are an expert programming assistant. When the user asks for code,
provide complete, working examples with brief inline comments for clarity.
Default to Python unless the user specifies a different language.
Proactively mention potential bugs, edge cases, or improvements.
Keep explanations brief — show don't tell. Format all code in proper code blocks.
```

**4. Creative Writer (storytelling and content)**
```
You are a creative writing assistant with a vivid imagination. You help with
stories, scripts, poems, blog posts, and other creative content.
You match the tone and style the user asks for. You make suggestions to
improve flow, character, and engagement. You never censor creative ideas
but keep content tasteful unless explicitly requested otherwise.
```

**5. Security Analyst (cybersecurity advisor)**
```
You are a cybersecurity expert specializing in home network security,
self-hosted infrastructure, and privacy best practices. You help identify
risks in configurations, suggest hardening measures, and explain threats
in plain English. You do not assist with offensive hacking activities.
You assume the user is trying to secure their own systems.
```

---

## 8. Model Selection Guide

Choosing the right model is like choosing the right tool from a toolbox. Here's a practical guide:

### Your Local Models

| Model Alias | Hardware | Best For | Speed |
|---|---|---|---|
| `brain-heavy` | Node A RX 7900 XT | Complex reasoning, long documents, accuracy-critical tasks | Slow (30–90s) |
| `brawn-fast` | Node B RTX 4070 | Quick answers, everyday chat, code snippets | Fast (5–15s) |
| `intel-vision` | Node C Arc A770 + llava | Image analysis, reading text in photos | Medium |

### Cloud Models (if you add them)

| Model | Best For | Cost |
|---|---|---|
| `gpt-4o` | Best overall quality for complex tasks | Paid per token |
| `gpt-4o-mini` | Fast, cheap, good quality for simple tasks | Paid per token |
| `claude-sonnet` | Long documents, nuanced writing, coding | Paid per token |
| `claude-haiku` | Very fast, very cheap, good for summaries | Paid per token |
| `gemini-flash` | Fast multimodal tasks, document analysis | Paid per token |
| `mistral-large` | Strong European privacy-focused alternative | Paid per token |

### Decision Guide

```
What kind of task?
│
├─ Looking at an image?
│    └─ Use: intel-vision
│
├─ Quick question, short answer?
│    └─ Use: brawn-fast (or gpt-4o-mini if you have cloud access)
│
├─ Long document analysis or summarization?
│    └─ Use: brain-heavy (or claude-sonnet for very long docs)
│
├─ Writing code?
│    └─ Use: brawn-fast or claude-sonnet
│
├─ Need maximum accuracy (medical, legal, complex reasoning)?
│    └─ Use: brain-heavy (or gpt-4o / claude-sonnet)
│
├─ Creative writing?
│    └─ Use: brain-heavy or claude-sonnet
│
└─ Privacy-critical (nothing should leave home)?
     └─ Use: brain-heavy or brawn-fast (local only)
```

---

## 9. Creating Custom Model Presets

A model preset is a saved configuration that combines a model + a system prompt + settings into one easy-to-select option. For example, you could create "Home Lab Helper" which automatically uses `brawn-fast` with the home lab system prompt.

### How to Create a Model Preset

1. Go to `http://192.168.1.6:3000` and log in
2. Click **Workspace** in the left sidebar
3. Click **Models**
4. Click **+ Create New Model**
5. Fill in the form:

   | Field | What to Enter |
   |---|---|
   | **Name** | A friendly name, e.g. `Home Lab Helper` |
   | **Base Model** | Choose `brawn-fast` from the dropdown |
   | **System Prompt** | Paste your chosen system prompt from Section 7 |
   | **Description** | Optional: a short note about what this preset is for |
   | **Profile Image** | Optional: upload or choose an icon |

6. Click **Save**

The preset now appears in your model selector dropdown alongside all other models. Selecting it automatically applies the system prompt and base model — no manual configuration needed each time.

### Ideas for Useful Presets

| Preset Name | Base Model | Purpose |
|---|---|---|
| Quick Chat | brawn-fast | Everyday quick questions |
| Deep Think | brain-heavy | Complex analysis and research |
| Code Buddy | brawn-fast | Programming help with code-focused prompt |
| Image Analyzer | intel-vision | Photo analysis with descriptive prompt |
| Privacy Mode | brain-heavy or brawn-fast | Fully local, no cloud, max privacy |

---

## 10. Using RAG — Chat with Your Documents

RAG stands for "Retrieval-Augmented Generation" — a fancy way of saying "chat with a document." You upload a PDF (or text file), and the AI can answer questions about its contents.

### How to Upload a Document and Ask Questions

1. Start a new chat in Open WebUI
2. Click the **paperclip icon** (📎) next to the message input box
3. Select your PDF, Word doc, or text file from your computer
4. Wait for it to upload and process (you'll see a small indicator)
5. Once it's processed, type your question in the chat:
   ```
   Can you summarize the main points of this document?
   ```
   or
   ```
   What does this document say about [specific topic]?
   ```
6. The AI reads the document and answers based on its contents

### Tips for Better Document Chats

- **Smaller documents work better** — if you have a 500-page book, try uploading just the relevant chapters
- **Ask specific questions** — instead of "tell me about this," try "what are the three main risks mentioned in section 2?"
- **PDF quality matters** — scanned PDFs with poor image quality may not extract text well; text-based PDFs work best
- If results seem wrong, try rephrasing your question or being more specific about what you're looking for

### Supported File Types

- PDF documents
- Plain text files (`.txt`, `.md`)
- Word documents (`.docx`)
- CSV spreadsheets (some versions)
- Web pages (paste URL in some versions)

---

## 11. Image Analysis with intel-vision

The `intel-vision` model uses **llava** (a visual AI model) running on Node C's Intel Arc A770 GPU. It can look at images and describe, analyze, or answer questions about them.

### How to Analyze an Image

1. In Open WebUI, select `intel-vision` from the model dropdown
2. Click the **paperclip/image icon** next to the message box
3. Upload your image (JPEG, PNG, etc.)
4. Type your question or instruction:
   ```
   What do you see in this image?
   ```
   or
   ```
   Read all the text visible in this photo.
   ```
   or
   ```
   What ingredients are in this fridge? What can I cook?
   ```
5. The AI analyzes the image and responds

### What intel-vision Can Do

- Describe what's in a photo
- Read text from photos (receipts, signs, whiteboards, screenshots)
- Identify objects, plants, animals
- Analyze charts and diagrams
- Count objects in an image
- Describe the mood or style of artwork

### What It Struggles With

- Very small or low-resolution text
- Complex multi-column documents (use document RAG instead)
- Real-time or live video (it only handles still images)
- Precise measurements or coordinates in images

---

## 12. Pipelines and Tools

Open WebUI in 2026 supports **Tools** and **Functions** — these let the AI do more than just talk. It can actually *do things*.

### Web Search Integration

Enable the AI to search the internet before answering:

1. Go to **Workspace → Tools** in Open WebUI
2. Look for a **Web Search** tool (or install one from the community tools)
3. Configure it with a search API key (DuckDuckGo, Brave Search, or Searx)
4. Enable the tool in a chat by clicking the **tools icon** (🔧) before sending a message
5. Ask: *"Search the web for the latest news about AMD GPU drivers"*

### Function Calling

Function calling lets the AI trigger actions on your system — like running scripts, querying your home automation, or checking your calendar.

1. Go to **Workspace → Functions**
2. You can write custom Python functions that the AI can call
3. Example: a function that checks the weather from a local weather station, or reads from Home Assistant sensors

> **Note:** Functions are an advanced feature. Start with basic chat before diving into functions.

### Image Generation Integration

If you have a Stable Diffusion instance running, you can connect it:

1. Go to **Settings → Images**
2. Set the **Image Generation** URL to your Stable Diffusion API endpoint
3. In chat, type: *"Generate an image of a cozy home lab setup"*

---

## 13. Knowledge Bases in Open WebUI

A **Knowledge Base** is a collection of documents that the AI can always reference — like giving it a library it can consult for every conversation.

### Setting Up a Knowledge Base

1. Go to **Workspace → Knowledge** in Open WebUI
2. Click **+ Create Knowledge Base**
3. Give it a name (e.g., "Home Lab Docs" or "My Recipes")
4. Upload documents: click **Add Files** and upload your PDFs or text files
5. Wait for processing (indexing takes a moment for large documents)
6. Click **Save**

### Using a Knowledge Base in Chat

1. Start a new chat
2. Click the **#** symbol or look for **Knowledge** in the chat options
3. Select your knowledge base
4. Now ask questions — the AI searches your knowledge base before answering

### Ideas for Knowledge Bases

| Knowledge Base | What to Put In It |
|---|---|
| Home Lab Docs | All your guide PDFs, setup notes, IP address tables |
| Home Manuals | PDF manuals for your appliances |
| Recipes | Recipe PDFs or text files |
| Work Notes | Meeting notes, project docs (privacy-safe since it's local!) |
| Medical Info | Personal health docs (stays on your network) |

---

## 14. Tips and Tricks for 2026

### Conversation History

- Open WebUI saves every conversation automatically
- Find old chats in the **sidebar** (left panel) under the date they happened
- Use the **search bar** at the top of the sidebar to search for a keyword across all past conversations
- **Pin important conversations** — right-click a chat title → Pin

### Sharing Chats

- Open a conversation you want to share
- Click the **share icon** (usually in the top-right of the chat)
- Get a shareable link — anyone on your network can view it (read-only)
- Great for sharing useful AI-generated answers with family members on your network

### Using Open WebUI as an API

Open WebUI itself exposes an API endpoint, meaning other apps can send it chat requests. This is useful for automations.

```bash
# Example: send a message via Open WebUI's API
curl http://192.168.1.6:3000/api/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-webui-api-key" \
  -d '{
    "model": "brawn-fast",
    "messages": [{"role": "user", "content": "What time is it?"}]
  }'
```

Find your API key in Open WebUI: **Profile → Settings → Account → API Keys**

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl + Shift + O` | Open new chat |
| `Ctrl + /` | Focus on message input |
| `Ctrl + Enter` | Send message |
| `Escape` | Cancel generation / stop response |

### Multi-Model Conversations

In newer versions of Open WebUI, you can send the *same message* to multiple models at once and compare their responses side-by-side. Look for a **multi-model** or **compare** button in the model selector.

### Regenerate and Edit

- Don't like the response? Click **Regenerate** (the circular arrow under the response) to try again
- You can also **edit your previous message** — click the pencil icon on your message, change it, and the AI will re-respond to the updated version

---

## 15. Troubleshooting

### ❌ Model not appearing in the Open WebUI dropdown

**Most likely causes and fixes:**

1. **LiteLLM connection not set up or broken**
   - Go to **Settings → Connections** and re-verify the connection
   - URL must be `http://192.168.1.222:4000/v1` (with `/v1` at the end)
   - Key must be exactly `sk-master-key`

2. **Model not in LiteLLM's config.yaml**
   - Check `/path/to/litellm/config.yaml` — the model must be listed there
   - After editing, restart LiteLLM: `docker compose -f litellm-stack.yml restart`

3. **LiteLLM itself is not running**
   - Visit `http://192.168.1.222:4000/health` — if it doesn't load, LiteLLM is down
   - Restart it via Portainer or command line

---

### ❌ "Connection refused" when saving settings

**Cause:** Open WebUI can't reach LiteLLM.

**Fixes:**
- Check that Node B is powered on and reachable: `ping 192.168.1.222`
- Check that LiteLLM's container is running (Portainer → Node B → Containers)
- Make sure the URL doesn't have a trailing slash: use `http://192.168.1.222:4000/v1` not `http://192.168.1.222:4000/v1/`
- Check firewall on Node B: `sudo ufw status` (if using UFW)

---

### ❌ Responses are very slow (more than 2 minutes)

**Cause:** The model is probably running on CPU instead of GPU.

**Fixes:**
- For Node A (AMD GPU): check that ROCm is working: `rocm-smi` on the host
- For Node B (NVIDIA GPU): check that CUDA is working: `nvidia-smi` on the host
- In the Docker container, check GPU access: `docker exec -it your-container nvidia-smi`
- If GPU isn't being used, the Docker container may be missing the GPU device mapping in `docker-compose.yml`
- Try switching to a lighter model like `mistral` or `phi3` while you debug

---

### ❌ "Invalid API key" error

**Cause:** The key you entered doesn't match what LiteLLM expects.

**Fixes:**
- The master key for your setup is `sk-master-key` — make sure there are no extra spaces
- Check LiteLLM's `config.yaml` for the `master_key` setting — it must match what you entered in Open WebUI
- If you changed the master key, update it everywhere: Open WebUI settings, Home Assistant, any other apps using it

---

### ❌ Open WebUI loads but the page is blank or broken

**Cause:** Browser cache issue or container crash.

**Fixes:**
- Hard refresh: `Ctrl + Shift + R` (Windows/Linux) or `Cmd + Shift + R` (Mac)
- Try a different browser or incognito/private window
- Check if the Open WebUI container (`chimera_face`) is running in Portainer
- Check container logs for errors: Portainer → chimera_face → Logs

---

### ❌ Uploaded document not being used in answers

**Cause:** Document wasn't processed correctly, or the AI isn't being told to use it.

**Fixes:**
- Re-upload the document — sometimes the first upload fails silently
- Make sure the document appears in the chat as an attachment (you should see a file pill above the input box)
- Try asking explicitly: *"Based ONLY on the uploaded document, answer this question: ..."*
- For knowledge bases, make sure you've selected the knowledge base in the chat before asking

---

### ❌ intel-vision not analyzing images

**Cause:** llava model isn't loaded on Node C, or the vision model isn't configured.

**Fixes:**
- SSH into Node C and run: `ollama pull llava`
- Check that `intel-vision` in LiteLLM's config points to the correct Ollama endpoint: `http://192.168.1.6:11434`
- Restart the Ollama container on Node C after pulling the model
- Try a direct test: `curl http://192.168.1.6:11434/api/tags` to see if llava appears in the model list

---

*Last updated for the Grand Unified AI Home Lab stack — 2026 edition. For post-installation verification and first-run tests, see `14_POST_INSTALL_LAYMENS_GUIDE.md`. For initial deployment, see the earlier numbered guides.*
