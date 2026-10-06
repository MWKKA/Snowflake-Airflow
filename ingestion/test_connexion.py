import os
import snowflake.connector

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    authenticator="SNOWFLAKE_JWT",                 # authentification par clé
    private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
    role="TRANSFORMER",
    warehouse="NYC_TAXI_WH",
    database="NYC_TAXI",
    schema="RAW",
)
cur = conn.cursor()
print(cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE()").fetchone())
conn.close()