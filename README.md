# Chat On Steroids — Plus Bridge

Bootstrap repository for a Windows-local ChatGPT companion derived from `totec448-spec/chat-on-steroids` (MIT).

The bootstrap workflow mirrors the upstream 1.9.4 source, preserves its UI and local executor, then applies the Plus Bridge transport layer. It does **not** unlock restricted OpenAI features or bypass account/rate limits; it uses the normal ChatGPT web UI as the conversation surface and keeps execution local.
