import { defineFunction } from "@aws-amplify/backend";

export const pushNotification = defineFunction({
  name: "push-notification-handler",
  entry: "./handler.ts",
  runtime: 20,
  timeoutSeconds: 30,
});
