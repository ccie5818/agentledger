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
});
