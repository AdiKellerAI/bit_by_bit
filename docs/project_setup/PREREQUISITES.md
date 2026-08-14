# AI Community Agent — Preparation Guide

Everything you need to prepare before writing the first line of code.

> **Updated:** Telegram is now the primary Agent channel. WhatsApp Community creation is unblocked and independent of any Meta Developer Account status.

This guide is intentionally simple. Follow it from top to bottom.

---

## 1. GitHub Account

**Purpose:** Store your source code and collaborate with AI tools like Cursor.

**Steps**
- Create a GitHub account (if you don't already have one).
- Create a new private repository.
- Name it something like: `ai-community-agent`
- Install Git on your computer (if not already installed).
- Clone the repository locally.

**Save**
- Repository URL

---

## 2. Install Cursor

**Purpose:** This will be your AI development environment.

**Steps**
- Download Cursor.
- Install it.
- Sign in.
- Open the GitHub repository.

No additional preparation is required.

---

## 3. OpenAI API

**Purpose:** Provides ChatGPT capabilities.

**Steps**
- Create an OpenAI account.
- Add a payment method.
- Open the API Dashboard.
- Create a new API Key.
- Copy the key immediately (it won't be shown again).

**Save**
```env
OPENAI_API_KEY=
```

---

## 4. Anthropic (Claude)

**Purpose:** Allows the agent to use Claude for complex questions.

**Steps**
- Create an Anthropic account.
- Add billing.
- Generate an API Key.

**Save**
```env
ANTHROPIC_API_KEY=
```

---

## 5. Google AI (Gemini)

**Purpose:** Optional low-cost model for simple requests.

**Steps**
- Create a Google AI Studio account.
- Create an API Key.

**Save**
```env
GEMINI_API_KEY=
```

---

## 6. Telegram Bot (Primary Agent Channel — do this now)

**Purpose:** This is the Agent's 1:1 channel for the MVP. Unlike WhatsApp Cloud API, this requires no business verification, no SMS gateway, and no developer account of any kind — it typically takes under two minutes.

**Steps**
- Open Telegram (any account is fine — your personal one works).
- Search for the user **@BotFather** and start a chat with it.
- Send the command `/newbot`.
- Choose a display name for the bot (e.g. "AI Community Agent").
- Choose a unique username ending in `bot` (e.g. `ai_community_agent_bot`).
- BotFather immediately replies with an HTTP API token.
- Optional: send `/setdescription`, `/setabouttext`, and `/setuserpic` to BotFather to finish the bot's profile.

**Save**
```env
TELEGRAM_BOT_TOKEN=
TELEGRAM_BOT_USERNAME=
```

---

## 7. Meta Developer Account (Optional / Future — WhatsApp Cloud API for the Agent)

**Purpose:** Only needed if/when you add a WhatsApp Cloud API adapter for the Agent, in addition to Telegram. **Not required for the MVP** — this must not block any other step.

**Status:** Previously blocked by SMS verification not arriving after multiple attempts, including a second phone number and going through Accounts Center directly. Leave this parked and revisit later via one of:
- Meta Business Manager verification first (`business.facebook.com`), then attach WhatsApp
- a WhatsApp Business Solution Provider (e.g. Twilio, 360dialog) that handles onboarding with their own support
- a fresh Meta account/device combination, to rule out an account-level block

**Note on the WhatsApp Business app:** You already have the free **WhatsApp Business app** installed (distinct from Cloud API — no developer account needed for the app itself). That's a head start for *this* step: it's the number you'll eventually migrate to Cloud API once Meta unblocks, so there's no separate number to set up later. It does not, by itself, unlock programmatic API access — that still runs through this step.

**Considered and rejected for now:** unofficial WhatsApp automation libraries (e.g. Baileys, whatsapp-web.js) can drive a WhatsApp number without Cloud API or a Meta Developer Account, by automating the WhatsApp Web protocol. This was deliberately not adopted for this project — it violates WhatsApp's Terms of Service, risks the number being banned, is unsupported and can break without notice, and doesn't fit the security posture the rest of this spec is built around (see PROJECT-SPEC.md §4.8). The Agent stays on Telegram until official Cloud API access is available.

**Steps (once unblocked)**
- Create a Meta Developer account.
- Verify your account if requested.
- Create a new App.
- Select **Business** as the app type.
- Add the **WhatsApp** product.

**Save (once unblocked)**
- App ID
- App Secret

---

## 8. WhatsApp Business Cloud API (Optional / Future — depends on step 7)

**Steps (once step 7 is unblocked)**
- Inside your Meta app, enable WhatsApp Cloud API.
- Get the temporary access token.
- Generate a permanent access token.
- Note the Phone Number ID.
- Note the WhatsApp Business Account ID.

**Save (once unblocked)**
```env
WHATSAPP_ACCESS_TOKEN=
PHONE_NUMBER_ID=
BUSINESS_ACCOUNT_ID=
```

---

## 9. WhatsApp Community (Human-Run Side — do this now, unrelated to steps 7–8)

**Purpose:** This is the human-administered community (Announcements + Sandbox). It's a completely separate surface from the Agent's 1:1 channel and has **no dependency on the Meta Developer Account or Cloud API** — it's a native feature of the regular WhatsApp app.

**Important — Business app limitation:** WhatsApp Communities are **not available in the WhatsApp Business app** (this is a real, current WhatsApp limitation, not an outdated-app or account issue). If you only see the option missing on your Business number, that's why. Create the Community from a **regular WhatsApp account** instead — this doesn't conflict with anything else in the plan: the WhatsApp Business number stays reserved for the future Cloud API migration (§7), and the Community is a fully separate track.

**Ownership decision:** the Community is created and owned by a **regular WhatsApp account belonging to a trusted household member** (not the WhatsApp Business number). Immediately after creation, add **your own number as a full admin** of both the Community and every group inside it — WhatsApp's "creator" role has some privileges a regular admin doesn't (e.g. it can't be demoted by other admins in some app versions), so day-to-day control and continuity should not depend on the creator account alone. Store both numbers in your credentials backup (§19) — do not write the actual phone numbers into this document or commit them to the repository.

**Steps**
- Open regular WhatsApp — not WhatsApp Business — either the mobile app or WhatsApp Web/Desktop (Community creation works from both now; use whichever is more convenient).
- Go to the **Communities** tab (mobile: bottom/top tab depending on OS; desktop: Communities icon above the chat list).
- Tap/click **New Community** (or the **+** / three-dot menu → New Community, depending on app version).
- Name it, add a description and icon.
- Create at least two groups inside it: one for **Announcements** (admin-only posting) and one for **Sandbox/Discussion** (open posting).
- Add your own number to the Community and to both groups, then promote it to **admin** in each (Community settings → Members → tap your number → Make community admin; repeat inside each group).
- Generate an invite link to share with employees.
- Post a pinned message in the Community explaining how to reach the Agent (the Telegram bot link from step 6, for now).

**Save**
- Community owner number (kept in your secrets/contacts store, not in this document)
- Your admin number (same)
- Community invite link
- Announcements group name
- Sandbox group name

---

## 10. Webhook

**Purpose:** Allows the Telegram Bot API (and later WhatsApp, if added) to send messages to your application.

**Steps**
- Create a webhook URL (later using your server).
- Register the webhook with Telegram using the Bot API's `setWebhook` call and your bot token.
- If/when WhatsApp Cloud API is added later, repeat the equivalent steps in Meta Developers (Configure Webhook, Verify Token, Subscribe to message events) — additive, not a replacement.

**Save**
```env
WEBHOOK_URL=
TELEGRAM_WEBHOOK_SECRET=
```
> Recommended, to verify inbound requests are really from Telegram.

---

## 11. Database

Choose one:
- PostgreSQL
- MySQL
- Supabase
- SQLite (development only)

**Create**
- Database
- Username
- Password

**Save**
```env
DATABASE_URL=
```

---

## 12. Redis (Optional)

Used for:
- Conversation memory
- Caching
- Session storage
- Idempotency / rate limiting

**Save**
```env
REDIS_URL=
```

---

## 13. Hosting

Choose one:
- Railway
- Render
- DigitalOcean
- Azure
- AWS

**Create**
- Account
- New project

**Save**
- Server URL

---

## 14. Domain Name (Optional)

If you want production deployment:
- Buy a domain.
- Point it to your server.

Example: `agent.mycompany.com`

---

## 15. Environment Variables

Create a `.env` file and add all your secrets.

```env
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
TELEGRAM_BOT_TOKEN=
TELEGRAM_WEBHOOK_SECRET=
DATABASE_URL=
REDIS_URL=

# WhatsApp Cloud API — leave blank until step 7/8 are unblocked
WHATSAPP_ACCESS_TOKEN=
PHONE_NUMBER_ID=
```

> Never commit this file to GitHub.

---

## 16. Test Telegram Account

**Prepare**
- One Telegram account for testing (can be your own).
- Message the bot directly to confirm the webhook and pipeline work end to end.

---

## 17. Knowledge Base

Prepare documents your AI should know:
- PDFs
- Word documents
- FAQs
- Podcast/article lists
- Curated public links
- Markdown files

Put everything into one folder:
```text
knowledge/
  ai_basics.md
  podcasts.md
  dev_tools.md
```

> Remember: PUBLIC information only for the POC — nothing internal, proprietary, or classified.

---

## 18. Sample Questions

Prepare around 50–100 questions people might ask, for example:
- "What is RAG?"
- "יש פודקאסט טוב למתחילים ב-AI?"
- "מה חדש בעולם ה-Agents?"
- "How can AI help with testing?"
- A few adversarial examples: attempts to paste secrets, credentials, or internal-looking data — to verify the sensitive-data detector blocks and alerts correctly.

These will be used for testing, including the security/sensitive-data pipeline.

---

## 19. Create a Secrets Backup

Store all important credentials securely in a password manager or encrypted vault:
- API Keys
- Telegram bot token
- Database passwords
- Domain credentials
- Hosting credentials
- GitHub credentials
- *(Later)* WhatsApp Cloud API credentials, once step 7/8 are unblocked

> Never store secrets in plain text files or send them over chat.

---

## 20. Final Checklist

**Agent channel (Telegram — do now)**
- [ ] Telegram bot created via @BotFather
- [ ] Bot token saved

**Community channel (WhatsApp — do now, independent of above)**
- [ ] WhatsApp Community created
- [ ] Announcements + Sandbox groups created
- [ ] Invite link saved

**Core**
- [ ] GitHub repository
- [ ] Cursor installed
- [ ] OpenAI API key
- [ ] Anthropic API key
- [ ] Gemini API key (optional)
- [ ] Database created
- [ ] Hosting account
- [ ] Webhook configured (Telegram)
- [ ] Knowledge documents
- [ ] Sample questions (including adversarial/sensitive-data test prompts)
- [ ] `.env` file ready
- [ ] Secure backup of all credentials

**Deferred / optional (not required for MVP)**
- [x] WhatsApp Business app already installed — number reserved for future Cloud API migration
- [ ] Meta Developer account
- [ ] WhatsApp Cloud API configured
- [ ] Permanent WhatsApp access token
- [ ] Phone Number ID

Once every non-deferred box is checked, you're ready to start building the AI Community Agent with Cursor.
