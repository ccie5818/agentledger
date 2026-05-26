import { defineStorage } from "@aws-amplify/backend";

export const storage = defineStorage({
  name: "marketplacePhotos",
  access: (allow) => ({
    "listings/*": [
      allow.guest.to(["get"]),
      allow.authenticated.to(["get", "write", "delete"]),
    ],
    "avatars/*": [
      allow.guest.to(["get"]),
      allow.authenticated.to(["get", "write", "delete"]),
    ],
  }),
});
