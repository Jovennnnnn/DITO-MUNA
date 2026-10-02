-- SAFE SQL SCHEMA UPDATE
-- Ito ay "safe" i-run kahit ilang beses dahil gumagamit ito ng stored procedure
-- para i-check muna kung exist na ang column bago ito idagdag.

DELIMITER //

CREATE PROCEDURE IF NOT EXISTS FixComplaintsTable()
BEGIN
    -- 1. Check at Idagdag ang 'is_archived' column kung wala pa
    IF NOT EXISTS (
        SELECT * FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'complaints'
        AND COLUMN_NAME = 'is_archived'
    ) THEN
        ALTER TABLE complaints ADD COLUMN is_archived TINYINT(1) DEFAULT 0;
    END IF;

    -- 2. Check at Idagdag ang 'deleted_by_resident' column kung wala pa
    IF NOT EXISTS (
        SELECT * FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'complaints'
        AND COLUMN_NAME = 'deleted_by_resident'
    ) THEN
        ALTER TABLE complaints ADD COLUMN deleted_by_resident TINYINT(1) DEFAULT 0;
    END IF;

    -- 3. Check at Idagdag ang 'admin_response' column kung wala pa
    IF NOT EXISTS (
        SELECT * FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'complaints'
        AND COLUMN_NAME = 'admin_response'
    ) THEN
        ALTER TABLE complaints ADD COLUMN admin_response TEXT DEFAULT NULL;
    END IF;

    -- 4. Siguraduhin na ang primary key ay 'complaint_id'
    -- (Kung ang gamit mo ay 'id', ang system natin sa backend ay naghahanap ng 'complaint_id')
    IF NOT EXISTS (
        SELECT * FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'complaints'
        AND COLUMN_NAME = 'complaint_id'
    ) THEN
        -- I-rename lang ang 'id' to 'complaint_id' kung 'id' ang pangalan nito
        IF EXISTS (
            SELECT * FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'complaints'
            AND COLUMN_NAME = 'id'
        ) THEN
            ALTER TABLE complaints CHANGE id complaint_id INT AUTO_INCREMENT;
        END IF;
    END IF;

END //

CREATE PROCEDURE IF NOT EXISTS FixSettingsColumns()
BEGIN
    -- Fix for 'users' table
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'email_notifications') THEN
        ALTER TABLE users ADD COLUMN email_notifications TINYINT(1) DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'app_notifications') THEN
        ALTER TABLE users ADD COLUMN app_notifications TINYINT(1) DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'auto_backup') THEN
        ALTER TABLE users ADD COLUMN auto_backup TINYINT(1) DEFAULT 0;
    END IF;

    -- Fix for 'residents' table
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'residents' AND COLUMN_NAME = 'email_notifications') THEN
        ALTER TABLE residents ADD COLUMN email_notifications TINYINT(1) DEFAULT 1;
    END IF;
    IF NOT EXISTS (SELECT * FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'residents' AND COLUMN_NAME = 'app_notifications') THEN
        ALTER TABLE residents ADD COLUMN app_notifications TINYINT(1) DEFAULT 1;
    END IF;
END //

DELIMITER ;

-- I-run ang procedures
CALL FixComplaintsTable();
CALL FixSettingsColumns();

-- Burahin ang procedures pagkatapos gamitin para malinis
DROP PROCEDURE FixComplaintsTable;
DROP PROCEDURE FixSettingsColumns;
