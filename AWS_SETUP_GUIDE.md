# AWS Amplify Gen 2 Setup Guide — Marketplace App

## What is Amplify Gen 2?

Gen 2 is the latest version of AWS Amplify. Instead of the old CLI-based workflow (`amplify add auth`), you now define your entire backend in **TypeScript** files. The backend is already written for you in the `amplify/` folder:

```
amplify/
├── auth/resource.ts      ← Cognito (sign up, sign in, email verification)
├── data/resource.ts      ← AppSync + DynamoDB (listings, messages, profiles)
├── storage/resource.ts   ← S3 (listing photos, avatars)
├── backend.ts            ← Ties everything together
├── package.json
└── tsconfig.json
```

---

## Step 1: Prerequisites

```bash
# Install Node.js 18+ (if not already installed)
brew install node

# Verify
node --version   # Should be 18.x or higher
npm --version
```

You also need an **AWS account**. Sign up at https://aws.amazon.com if you don't have one.

---

## Step 2: Install Dependencies

```bash
cd AgentLedger

# Install the Amplify backend dependencies
cd amplify
npm install
cd ..
```

---

## Step 3: Start the Cloud Sandbox

The cloud sandbox creates a personal dev environment on AWS that hot-reloads when you change your backend files:

```bash
npx ampx sandbox
```

This will:
1. Prompt you to sign in to your AWS account (first time only)
2. Deploy Cognito, AppSync, DynamoDB, and S3 to your AWS account
3. Generate an `amplify_outputs.json` file in your project root

**Leave this running** while you develop. It watches for changes to your `amplify/` files and redeploys automatically.

---

## Step 4: Add `amplify_outputs.json` to Xcode

1. Find the generated `amplify_outputs.json` file in your project root
2. **Drag and drop** it from Finder into your Xcode project (into the `AgentLedger` group)
3. Make sure "Copy items if needed" is checked and it's added to the app target

---

## Step 5: Add Amplify Swift SDK to Xcode

In Xcode: **File → Add Package Dependencies...**

Add these two packages:

| Package | URL |
|---------|-----|
| Amplify Swift | `https://github.com/aws-amplify/amplify-swift` |
| Amplify UI Authenticator | `https://github.com/aws-amplify/amplify-ui-swift-authenticator` |

For both, select **Up to Next Major Version**.

When prompted, add these libraries to your app target:
- `Amplify`
- `AWSCognitoAuthPlugin`
- `AWSAPIPlugin`
- `AWSS3StoragePlugin`

---

## Step 6: Generate Swift Model Code

Run this to generate typed Swift models from your GraphQL schema:

```bash
npx ampx generate graphql-client-code \
  --format modelgen \
  --model-target swift \
  --out AgentLedger/AmplifyModels
```

This creates an `AmplifyModels/` folder with Swift structs matching your data schema (Listing, Conversation, Message, UserProfile). Add this folder to your Xcode project.

---

## Step 7: Activate the Real Amplify Code

Open `AgentLedger/Services/AmplifyService.swift` and:

1. **Uncomment** the imports at the top:
   ```swift
   import Amplify
   import AWSCognitoAuthPlugin
   import AWSAPIPlugin
   import AWSS3StoragePlugin
   ```

2. In the `configure()` method, **uncomment** the real implementation:
   ```swift
   try Amplify.add(plugin: AWSCognitoAuthPlugin())
   try Amplify.add(plugin: AWSAPIPlugin(modelRegistration: AmplifyModels()))
   try Amplify.add(plugin: AWSS3StoragePlugin())
   try Amplify.configure(with: .amplifyOutputs)
   ```

3. In each method (`signIn`, `signUp`, `createListing`, etc.), **uncomment** the `// REAL` blocks and **delete** the `// SIMULATED` blocks.

---

## Step 8: Build & Run

1. Select an iPhone simulator in Xcode
2. Press **Cmd+R** to build and run
3. Create an account on the sign-up screen
4. Check your email for the verification code
5. Start posting listings!

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│                 iOS App (Swift)                    │
│                                                    │
│  AuthView ←→ Amplify.Auth     ←→ AWS Cognito     │
│  HomeView ←→ Amplify.API      ←→ AWS AppSync     │
│  PostView ←→ Amplify.Storage  ←→ Amazon S3       │
│  ChatView ←→ Subscriptions    ←→ Real-time WS    │
└──────────────────────────────────────────────────┘
         │
         ▼  amplify_outputs.json (auto-generated)
┌──────────────────────────────────────────────────┐
│            amplify/ (TypeScript)                   │
│                                                    │
│  backend.ts     ← defineBackend({ auth, data, … })│
│  auth/          ← defineAuth({ loginWith: email }) │
│  data/          ← defineData({ schema })           │
│  storage/       ← defineStorage({ name, access })  │
└──────────────────────────────────────────────────┘
         │
         ▼  npx ampx sandbox (deploys to AWS)
┌──────────────────────────────────────────────────┐
│               AWS Cloud                            │
│                                                    │
│  Cognito    → User authentication + email verify  │
│  AppSync    → GraphQL API + real-time subs        │
│  DynamoDB   → Database (auto-provisioned)         │
│  S3         → Photo storage                       │
└──────────────────────────────────────────────────┘
```

---

## Useful Commands

| Command | What it does |
|---------|-------------|
| `npx ampx sandbox` | Start dev sandbox (hot-reloads backend changes) |
| `npx ampx sandbox delete` | Tear down your sandbox environment |
| `npx ampx generate graphql-client-code --format modelgen --model-target swift --out ./AmplifyModels` | Regenerate Swift models after schema changes |
| `npx ampx generate outputs --out-dir ./AgentLedger` | Regenerate amplify_outputs.json |

---

## Deploy to Production

When you're ready to go live, connect your repo to AWS Amplify Hosting:

1. Push your code to GitHub
2. Go to https://console.aws.amazon.com/amplify
3. Click **New app → Host web app**
4. Connect your GitHub repo
5. Amplify will auto-detect the `amplify/` folder and deploy your backend
6. Each git push auto-deploys updates

---

## Estimated AWS Costs

For a small marketplace (< 1,000 users):

| Service   | Free Tier                    | After Free Tier       |
|-----------|------------------------------|-----------------------|
| Cognito   | 50,000 MAU free              | $0.0055/MAU           |
| AppSync   | 250K queries/mo free         | $4.00/million queries |
| DynamoDB  | 25 GB + 25 read/write free   | ~$1.25/million reads  |
| S3        | 5 GB + 20K GETs free         | $0.023/GB             |

**Typical monthly cost: $0–5/month** within the free tier.

---

## What's Included in Your Backend

### Auth (`amplify/auth/resource.ts`)
- Email-based sign up with verification code
- Configurable password policy (8+ chars, upper/lower/numbers)
- Optional phone number and preferred username

### Data (`amplify/data/resource.ts`)
- **Listing** — title, description, price, category, photos, location, condition
- **Conversation** — links buyer ↔ seller for a listing, with messages
- **Message** — belongs to a conversation, tracks read status
- **UserProfile** — name, email, phone, location, avatar
- Authorization: owners can CRUD their own data, everyone can read listings

### Storage (`amplify/storage/resource.ts`)
- `listings/*` — listing photos (public read, auth write)
- `avatars/*` — profile photos (public read, auth write)
