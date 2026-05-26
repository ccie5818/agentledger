import boto3

REGION = "us-east-1"


def find_table_name(dynamodb_client):
    """Find the UserProfile table name (Amplify adds a suffix)."""
    paginator = dynamodb_client.get_paginator("list_tables")
    for page in paginator.paginate():
        for name in page["TableNames"]:
            if "UserProfile" in name:
                return name
    return None


def main():
    dynamodb = boto3.client("dynamodb", region_name=REGION)

    # Step 1: Find the table
    table_name = find_table_name(dynamodb)
    if not table_name:
        print("ERROR: Could not find UserProfile table in DynamoDB!")
        return
    print(f"Found table: {table_name}\n")

    # Step 2: Scan all items
    print("Scanning all UserProfile records...")
    all_items = []
    scan_kwargs = {"TableName": table_name}
    while True:
        resp = dynamodb.scan(**scan_kwargs)
        all_items.extend(resp.get("Items", []))
        if "LastEvaluatedKey" in resp:
            scan_kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
        else:
            break

    print(f"Total records: {len(all_items)}\n")

    # Step 3: Group by owner
    owners = {}
    for item in all_items:
        owner = item.get("owner", {}).get("S", "unknown")
        pid = item.get("id", {}).get("S", "?")
        token = item.get("deviceToken", {}).get("S") if "deviceToken" in item else None
        name = item.get("name", {}).get("S", "?")
        email = item.get("email", {}).get("S", "?")
        updated = item.get("updatedAt", {}).get("S", "")

        if owner not in owners:
            owners[owner] = []
        owners[owner].append({
            "id": pid,
            "token": token,
            "name": name,
            "email": email,
            "updatedAt": updated,
        })

    # Step 4: For each owner, pick the best profile to keep
    to_delete = []
    to_keep = []

    for owner, profiles in owners.items():
        if len(profiles) == 1:
            to_keep.append(profiles[0])
            continue

        # Sort: prefer profiles with token, then by most recently updated
        profiles.sort(key=lambda p: (
            1 if p["token"] else 0,  # has token = better
            p["updatedAt"],           # newer = better
        ), reverse=True)

        best = profiles[0]
        to_keep.append(best)
        for p in profiles[1:]:
            to_delete.append(p)

    # Step 5: Show summary
    print("=== Profiles to KEEP (one per user) ===")
    for p in to_keep:
        print(f"  {p['email']:30s}  id={p['id']}  token={'yes' if p['token'] else 'no'}")

    print(f"\n=== Profiles to DELETE: {len(to_delete)} duplicates ===")
    for p in to_delete:
        print(f"  {p['email']:30s}  id={p['id']}  token={'yes' if p['token'] else 'no'}")

    if not to_delete:
        print("\nNo duplicates to delete! All clean.")
        return

    confirm = input(f"\nDelete {len(to_delete)} duplicate profiles? (yes/no): ").strip().lower()
    if confirm != "yes":
        print("Aborted.")
        return

    # Step 6: Delete
    print(f"\nDeleting {len(to_delete)} duplicates...")
    success = 0
    failed = 0
    for p in to_delete:
        try:
            dynamodb.delete_item(
                TableName=table_name,
                Key={"id": {"S": p["id"]}}
            )
            success += 1
            print(f"  Deleted: {p['id']}")
        except Exception as e:
            failed += 1
            print(f"  FAILED:  {p['id']} — {e}")

    print(f"\nDone! Deleted {success}, failed {failed}")
    print(f"Remaining profiles: {len(to_keep)}")


if __name__ == "__main__":
    main()
