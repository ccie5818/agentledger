import { defineBackend } from "@aws-amplify/backend";
import { auth } from "./auth/resource.js";
import { data } from "./data/resource.js";
import { storage } from "./storage/resource.js";
import { pushNotification } from "./functions/push-notification/resource.js";
import { StartingPosition } from "aws-cdk-lib/aws-lambda";
import { DynamoEventSource } from "aws-cdk-lib/aws-lambda-event-sources";
import * as iam from "aws-cdk-lib/aws-iam";

const backend = defineBackend({
  auth,
  data,
  storage,
  pushNotification,
});

// ─── Wire Lambda to Message table DynamoDB stream ────────
const messageTable = backend.data.resources.tables["Message"];
const userProfileTable = backend.data.resources.tables["UserProfile"];
const lambdaFunction = backend.pushNotification.resources.lambda;

// Pass the UserProfile table name to the Lambda via environment variable
backend.pushNotification.addEnvironment(
  "USERPROFILE_TABLE_NAME",
  userProfileTable.tableName
);

// Pass the SNS Platform Application ARN for APNs push notifications
// IMPORTANT: Replace this with your actual SNS Platform Application ARN from AWS Console
// To create one: AWS Console → SNS → Push notifications → Platform applications → Create
backend.pushNotification.addEnvironment(
  "SNS_PLATFORM_APP_ARN",
  "arn:aws:sns:us-east-1:513300627165:app/APNS_SANDBOX/CraigslistApp_APNS"
);

// Grant the Lambda read access to the UserProfile table (to look up device tokens)
userProfileTable.grantReadData(lambdaFunction);

// Grant SNS publish permissions to the Lambda
lambdaFunction.addToRolePolicy(
  new iam.PolicyStatement({
    actions: [
      "sns:Publish",
      "sns:CreatePlatformEndpoint",
      "sns:GetEndpointAttributes",
    ],
    resources: ["*"], // Scope to your SNS platform ARN in production
  })
);

// Attach the DynamoDB stream trigger — only fires on new inserts
lambdaFunction.addEventSource(
  new DynamoEventSource(messageTable, {
    startingPosition: StartingPosition.LATEST,
    batchSize: 10,
    retryAttempts: 2,
    filters: [
      {
        pattern: JSON.stringify({
          eventName: ["INSERT"],
        }),
      },
    ],
  })
);
