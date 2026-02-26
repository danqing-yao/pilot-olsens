-- #3687 Entered bids from 20241201 to 20251201
WITH auction_inventory AS (
    SELECT  
        a.auctionid,
        a.enddate,
        i.id AS inventoryid
    FROM Auction a
    JOIN Inventory i ON i.auctionsessionid = a.auctionid
    WHERE 
        a.enddate >= '2025-01-01'
        AND a.enddate < '2026-01-01'
)
SELECT
    ai.*,
    e.EnteredBidId,
    e.WebUserid,
    e.amount        AS bid_amount,
    e.bidtime,
    e.bidtype
FROM auction_inventory AS ai
LEFT JOIN EnteredBid AS e ON e.inventoryid = ai.inventoryid
WHERE e.bidtime IS NOT NULL
ORDER BY ai.inventoryid, e.bidtime;