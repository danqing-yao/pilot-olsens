SELECT
  l.lot_id,
  l.title,
  SUBSTRING_INDEX(l.url, '/', -1) AS inventoryId,
  l.url,
  l.auction_house_id,
  l.category_id,
  c.name AS category_name,
  l.created,
  l.updated
FROM lots_archived_31052025 l
LEFT JOIN categories c
  ON l.category_id = c.category_id
WHERE l.auction_house_id = '3687'
  AND l.created >= '2024-12-01'
  AND l.created <  '2025-06-01';