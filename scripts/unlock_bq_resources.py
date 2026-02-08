from google.cloud import bigquery

def unlock_table(project_id, dataset_id, table_id):
    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{dataset_id}.{table_id}"
    
    try:
        table = client.get_table(table_ref)
        if table.deletion_protection: # Only update if needed
            print(f"Unlocking {table_ref}...")
            table.deletion_protection = False
            client.update_table(table, ["deletion_protection"])
            print(f"Successfully unlocked {table_ref}")
        else:
            print(f"{table_ref} is already unlocked.")
    except Exception as e:
        print(f"Error unlocking {table_ref}: {e}")

if __name__ == "__main__":
    # Project ID
    project_id = "paris-mobility-pulse" # adjust if needed or pull from env
    
    # Tables to unlock
    unlock_table(project_id, "pmp_ops", "velib_station_status_curated_dlq")
    unlock_table(project_id, "pmp_marts", "velib_totals_hourly")
