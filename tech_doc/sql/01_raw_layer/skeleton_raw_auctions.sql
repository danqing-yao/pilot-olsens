-- ============================================================
-- Olséns 2025 Auction & Inventory Extraction (Skeleton Olsens DB)
-- ------------------------------------------------------------
-- Purpose : Extract all auctions ending in 2025 (aligned with
--           Skeleton's settlement logic based on auction enddate),
--           along with inventory, hammer price, initial bid price,
--           winner, and commission information.
-- Scope   : Auctions with enddate between 2025-01-01 and 2025-12-31
-- Tables  : Auction, Inventory, UnifiedCategory, InventoryWon,
--           WinnerTracking, BidAuditLog
-- Note    : initialbidprice falls back to hammeredprice (via COALESCE)
--           when no BidAuditLog record exists for that inventory item.
-- ============================================================
SELECT  
    a.auctionid,
    a.startdate,
    a.enddate,
    FORMAT(a.enddate, 'yyyy-MM') AS month,
    i.id,
    uc.name AS skeletoncategory,
    i.enddate       AS inventory_enddate,
    iw.amount       AS hammeredprice,
    COALESCE(bal.initialbidprice, iw.amount) as initialbidprice,
    iw.bidid,
    wt.userid as winnerid,
    iw.amount * iw.buyerspremium / 100 as buyerspremium,
    iw.currentcommission
FROM Auction a
JOIN Inventory i ON i.auctionsessionid = a.auctionid
LEFT JOIN unifiedcategory AS uc ON i.categoryid = uc.categoryid
LEFT JOIN inventorywon AS iw ON iw.inventoryid = i.id
LEFT JOIN winnertracking as wt ON iw.winnertrackingid = wt.id
LEFT JOIN (
    -- Get minimum non-NULL currenthighbid per inventoryid
    SELECT 
        inventoryid,
        MIN(currenthighbid) as initialbidprice
    FROM BidAuditLog
    WHERE currenthighbid IS NOT NULL
    GROUP BY inventoryid
) bal
    ON iw.inventoryid = bal.inventoryid
WHERE 
    a.enddate >= '2025-01-01'
    AND a.enddate < '2026-01-01'
ORDER BY StartDate;