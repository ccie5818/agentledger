import { type ClientSchema, a, defineData } from "@aws-amplify/backend";

const schema = a.schema({
  // ─── Listing ───────────────────────────────────────────
  Listing: a
    .model({
      title: a.string().required(),
      description: a.string().required(),
      price: a.float(),
      category: a.enum([
        "FOR_SALE",
        "HOUSING",
        "JOBS",
        "SERVICES",
        "COMMUNITY",
        "GIGS",
      ]),
      subcategory: a.string().required(),
      imageKeys: a.string().array(),
      location: a.string().required(),
      neighborhood: a.string().required(),
      condition: a.enum(["NEW", "LIKE_NEW", "GOOD", "FAIR", "SALVAGE"]),
      listingStatus: a.enum(["ACTIVE", "SOLD", "WITHDRAWN"]),
      sellerID: a.string().required(),
      sellerName: a.string().required(),
      isActive: a.boolean().default(true),
      conversations: a.hasMany("Conversation", "listingID"),
    })
    .authorization((allow) => [
      allow.owner(),
      allow.authenticated().to(["read"]),
      allow.guest().to(["read"]),
    ]),

  // ─── Conversation ──────────────────────────────────────
  // Auth: any authenticated user can create; both buyer and seller can
  // read/update/delete via authenticated() — we filter by buyerID/sellerID
  // in queries to only return relevant conversations.
  Conversation: a
    .model({
      listingID: a.id().required(),
      listing: a.belongsTo("Listing", "listingID"),
      listingTitle: a.string().required(),
      buyerID: a.string().required(),
      buyerName: a.string(),
      sellerID: a.string().required(),
      sellerName: a.string(),
      lastMessage: a.string(),
      lastMessageAt: a.datetime(),
      messages: a.hasMany("Message", "conversationID"),
    })
    .authorization((allow) => [
      allow.authenticated(),
    ]),

  // ─── Message ───────────────────────────────────────────
  // Auth: any authenticated user can CRUD — we rely on the parent
  // Conversation's buyerID/sellerID to enforce logical access.
  Message: a
    .model({
      conversationID: a.id().required(),
      conversation: a.belongsTo("Conversation", "conversationID"),
      senderID: a.string().required(),
      recipientID: a.string().required(),
      text: a.string().required(),
      isRead: a.boolean().default(false),
      status: a.enum(["SENT", "DELIVERED", "READ"]),
    })
    .authorization((allow) => [
      allow.authenticated(),
    ]),

  // ─── UserProfile ───────────────────────────────────────
  UserProfile: a
    .model({
      name: a.string().required(),
      email: a.string().required(),
      phone: a.string(),
      location: a.string(),
      neighborhood: a.string(),
      avatarKey: a.string(),
      favoriteListingIDs: a.string().array(),
      hiddenConversationIDs: a.string().array(),
      deviceToken: a.string(),
      platform: a.enum(["IOS", "ANDROID"]),
    })
    .authorization((allow) => [
      allow.owner(),
      allow.authenticated().to(["read"]),
    ]),
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: "userPool",
    apiKeyAuthorizationMode: {
      expiresInDays: 30,
    },
  },
});
