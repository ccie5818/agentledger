import { defineAuth } from "@aws-amplify/backend";

export const auth = defineAuth({
  loginWith: {
    email: {
      verificationEmailStyle: "CODE",
      verificationEmailSubject: "Welcome to Marketplace! Verify your email",
      verificationEmailBody: (createCode) =>
        `Your verification code is: ${createCode()}`,
    },
  },
  // Send Cognito emails through Amazon SES instead of the default sender
  // (which is capped at 50 emails/day). Requires the domain below to be a
  // verified SES identity in us-east-1 with DKIM, and SES production access.
  senders: {
    email: {
      fromEmail: "noreply@dfmi.app",
      fromName: "AgentLedger",
    },
  },
});
