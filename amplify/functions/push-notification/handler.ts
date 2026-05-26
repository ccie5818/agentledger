import { DynamoDBStreamEvent } from "aws-lambda";
import {
  SNSClient,
  PublishCommand,
  CreatePlatformEndpointCommand,
} from "@aws-sdk/client-sns";
import {
  DynamoDBClient,
  QueryCommand,
} from "@aws-sdk/client-dynamodb";
import { unmarshall } from "@aws-sdk/util-dynamodb";

const sns = new SNSClient({});
const dynamodb = new DynamoDBClient({});

// Table names are injected via environment or derived from the event
const USER_PROFILE_TABLE = process.env.USERPROFILE_TABLE_NAME || "";
const PLATFORM_APP_ARN = process.env.SNS_PLATFORM_APP_ARN || "";

interface MessageRecord {
  id: string;
  conversationID: string;
  senderID: string;
  recipientID: string;
  text: string;
  isRead: boolean;
  status: string;
  owner: string;
  createdAt: string;
}

interface UserProfileRecord {
  id: string;
  owner: string;
  name: string;
  deviceToken?: string;
  platform?: string;
}

export const handler = async (event: DynamoDBStreamEvent): Promise<void> => {
  console.log("Push notification handler triggered", JSON.stringify(event, null, 2));

  for (const record of event.Records) {
    // Only process new message inserts
    if (record.eventName !== "INSERT" || !record.dynamodb?.NewImage) {
      continue;
    }

    const newMessage = unmarshall(
      record.dynamodb.NewImage as any
    ) as MessageRecord;

    console.log("New message:", JSON.stringify(newMessage));

    // Skip if no recipientID
    if (!newMessage.recipientID) {
      console.log("No recipientID, skipping");
      continue;
    }

    try {
      // Look up the recipient's device token from UserProfile table
      const recipientProfile = await getRecipientProfile(newMessage.recipientID);

      if (!recipientProfile) {
        console.log(`No UserProfile found for recipient ${newMessage.recipientID}`);
        continue;
      }

      console.log(`Found UserProfile for recipient: id=${recipientProfile.id}, owner=${recipientProfile.owner}, deviceToken=${recipientProfile.deviceToken || "EMPTY"}, platform=${recipientProfile.platform || "EMPTY"}`);

      if (!recipientProfile.deviceToken) {
        console.log(`UserProfile exists but deviceToken is empty for ${newMessage.recipientID}`);
        continue;
      }

      // Send the push notification
      await sendPushNotification(
        recipientProfile.deviceToken,
        recipientProfile.platform || "IOS",
        newMessage.text,
        newMessage.senderID,
        newMessage.conversationID
      );

      console.log(`Push notification sent to ${newMessage.recipientID}`);
    } catch (error) {
      console.error(`Failed to send push to ${newMessage.recipientID}:`, error);
    }
  }
};

async function getRecipientProfile(
  ownerID: string
): Promise<UserProfileRecord | null> {
  // Amplify Gen 2 owner field may be stored as just "sub" or "sub::username"
  // We scan and check for both exact match and begins_with match
  const { ScanCommand } = await import("@aws-sdk/client-dynamodb");

  console.log(`Looking up UserProfile for owner containing: ${ownerID}`);
  console.log(`UserProfile table: ${USER_PROFILE_TABLE}`);

  // Scan all profiles and find matching owner (handles sub::username format)
  const scanResult = await dynamodb.send(
    new ScanCommand({
      TableName: USER_PROFILE_TABLE,
    })
  );

  if (!scanResult.Items || scanResult.Items.length === 0) {
    console.log("No UserProfile records found in table at all!");
    return null;
  }

  console.log(`Found ${scanResult.Items.length} total UserProfile records`);

  // Find the best match — prefer one with a deviceToken
  let bestMatch: UserProfileRecord | null = null;

  for (const item of scanResult.Items) {
    const profile = unmarshall(item) as UserProfileRecord;
    const profileOwner = profile.owner || "";

    // Match: exact, starts with, or contains the recipientID
    if (
      profileOwner === ownerID ||
      profileOwner.startsWith(ownerID) ||
      profileOwner.includes(ownerID)
    ) {
      console.log(`  MATCH: id=${profile.id} owner=${profileOwner} token=${profile.deviceToken || "EMPTY"}`);
      // Prefer a profile that has a device token
      if (profile.deviceToken) {
        return profile;
      }
      if (!bestMatch) {
        bestMatch = profile;
      }
    } else {
      console.log(`  skip: id=${profile.id} owner=${profileOwner}`);
    }
  }

  return bestMatch;
}

async function sendPushNotification(
  deviceToken: string,
  platform: string,
  messageText: string,
  senderID: string,
  conversationID: string
): Promise<void> {
  if (!PLATFORM_APP_ARN) {
    console.warn("SNS_PLATFORM_APP_ARN not configured, skipping push");
    return;
  }

  // Create/get the platform endpoint for this device
  const endpointResponse = await sns.send(
    new CreatePlatformEndpointCommand({
      PlatformApplicationArn: PLATFORM_APP_ARN,
      Token: deviceToken,
    })
  );

  const endpointArn = endpointResponse.EndpointArn;
  if (!endpointArn) {
    console.error("Failed to create/get SNS endpoint");
    return;
  }

  // Truncate message for notification preview
  const preview =
    messageText.length > 100
      ? messageText.substring(0, 97) + "..."
      : messageText;

  // Build the APNs payload
  const apnsPayload = {
    aps: {
      alert: {
        title: "New Message",
        body: preview,
      },
      sound: "default",
      badge: 1,
      "mutable-content": 1,
    },
    conversationID: conversationID,
    senderID: senderID,
  };

  // Publish to SNS
  const message =
    platform === "IOS"
      ? JSON.stringify({
          APNS: JSON.stringify(apnsPayload),
          APNS_SANDBOX: JSON.stringify(apnsPayload),
        })
      : JSON.stringify({
          GCM: JSON.stringify({
            notification: {
              title: "New Message",
              body: preview,
            },
            data: {
              conversationID,
              senderID,
            },
          }),
        });

  await sns.send(
    new PublishCommand({
      TargetArn: endpointArn,
      Message: message,
      MessageStructure: "json",
    })
  );
}
