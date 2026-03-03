CREATE OR REPLACE TABLE `barnebys-skeleton.pilot_olsens.raw_bbys_lots`
CLUSTER BY inventoryId, category_id
OPTIONS(
  description = "Deduplicated lots data combined from AWS and Azure sources, keeping latest record per inventoryId"
)
AS
SELECT
  lot_id,
  title,
  inventoryId,
  url,
  auction_house_id,
  category_id,
  category_name,
  created,
  updated
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY inventoryId
      ORDER BY created DESC
    ) AS rn
  FROM (
    SELECT * FROM `barnebys-skeleton.pilot_olsens.raw_bbys_aws_lots`
    UNION DISTINCT
    SELECT * FROM `barnebys-skeleton.pilot_olsens.raw_bbys_azure_lots`
  )
)
WHERE rn = 1;
