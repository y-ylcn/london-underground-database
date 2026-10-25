-- London Underground Transportation Database System --
-- Author: Yasin Yalcin --
-- All data, triggers, views and queries were tested in the Oracle Live SQL environment. --
--------------------------------------------------------------------------------------------

--------------------- DROP TABLES (reverse order because of foreign keys) -------------------

DROP TABLE CheckOut;
DROP TABLE CheckIn;
DROP TABLE StationLine;
DROP TABLE Ticket;
DROP TABLE BankCard;
DROP TABLE OysterCard;
DROP TABLE PassengerCard;
DROP TABLE Holiday;
DROP TABLE Line;
DROP TABLE Station;


------------------ CREATE TABLES -----------------------

------- Station Table -------

CREATE TABLE Station
    (StationID VARCHAR2(10) NOT NULL,
    StationName VARCHAR2(50) NOT NULL,
    HasBarrier VARCHAR2(5) NOT NULL,
    Zone NUMBER(1) NOT NULL,
    CONSTRAINT pk_station PRIMARY KEY (StationID),
    CONSTRAINT chk_barrier CHECK (HasBarrier IN ('TRUE', 'FALSE')),
    CONSTRAINT chk_zone CHECK (Zone BETWEEN 1 AND 6));

------- Line Table -------

CREATE TABLE Line
    (LineID VARCHAR2(10) NOT NULL,
    LineName VARCHAR2(30) NOT NULL,
    CONSTRAINT pk_line PRIMARY KEY (LineID));

------- Holiday Table -------

CREATE TABLE Holiday
    (HolidayDate DATE NOT NULL,
    HolidayName VARCHAR2(50) NOT NULL,
    CONSTRAINT pk_holiday PRIMARY KEY (HolidayDate));

------- PassengerCard -------

CREATE TABLE PassengerCard
    (CardID VARCHAR2(20) NOT NULL,
    CardType VARCHAR2(10) NOT NULL,
    CONSTRAINT pk_passengercard PRIMARY KEY (CardID),
    CONSTRAINT chk_cardtype CHECK (CardType IN ('Oyster', 'BankCard', 'Ticket')));

------- OysterCard -------

CREATE TABLE OysterCard
    (CardID VARCHAR2(20) NOT NULL,
    CardHolderName VARCHAR2(50),
    CreditAmount NUMBER(6, 2) NOT NULL,
    CONSTRAINT pk_oystercard PRIMARY KEY (CardID),
    CONSTRAINT fk_oyster FOREIGN KEY (CardID) REFERENCES PassengerCard(CardID));

------- BankCard -------

CREATE TABLE BankCard
    (CardID VARCHAR2(20) NOT NULL,
    CardHolderName VARCHAR2(50) NOT NULL,
    ExpirationDate DATE NOT NULL,
    CONSTRAINT pk_bankcard PRIMARY KEY (CardID),
    CONSTRAINT fk_bankcard FOREIGN KEY (CardID) REFERENCES PassengerCard(CardID));

------- Ticket -------

CREATE TABLE Ticket
    (CardID VARCHAR2(20) NOT NULL,
    ValidUntil DATE NOT NULL,
    CONSTRAINT pk_ticket PRIMARY KEY (CardID),
    CONSTRAINT fk_ticket FOREIGN KEY (CardID) REFERENCES PassengerCard(CardID));

------- StationLine -------

CREATE TABLE StationLine
    (StationID VARCHAR2(10) NOT NULL,
    LineID VARCHAR2(10) NOT NULL,
    CONSTRAINT pk_stationline PRIMARY KEY (StationID, LineID),
    CONSTRAINT fk_stationline_station FOREIGN KEY (StationID) REFERENCES Station(StationID),
    CONSTRAINT fk_stationline_line FOREIGN KEY (LineID) REFERENCES Line(LineID));

------- CheckIn -------

CREATE TABLE CheckIn
    (CheckInID VARCHAR2(10) NOT NULL,
    CardID VARCHAR2(20) NOT NULL,
    StationID VARCHAR2(10) NOT NULL,
    LineID VARCHAR2(10) NOT NULL,
    CheckInTime DATE NOT NULL,
    CheckInType VARCHAR2(15) NOT NULL,
    CONSTRAINT pk_checkin PRIMARY KEY (CheckInID),
    CONSTRAINT fk_checkin_card FOREIGN KEY (CardID) REFERENCES PassengerCard(CardID),
    CONSTRAINT fk_checkin_station FOREIGN KEY (StationID) REFERENCES Station(StationID),
    CONSTRAINT fk_checkin_line FOREIGN KEY (LineID) REFERENCES Line(LineID),
    CONSTRAINT chk_checkintype CHECK (CheckInType IN ('Standard', 'PinkReader')));

-------- CheckOut -------

CREATE TABLE CheckOut
    (CheckOutID VARCHAR2(10) NOT NULL,
    CardID VARCHAR2(20) NOT NULL,
    StationID VARCHAR2(10) NOT NULL,
    LineID VARCHAR2(10) NOT NULL,
    CheckOutTime DATE NOT NULL,
    FareAmount NUMBER(5, 2) NOT NULL,
    PreviousCredit NUMBER(6, 2),
    NextCredit NUMBER(6, 2),
    CONSTRAINT pk_checkout PRIMARY KEY (CheckOutID),
    CONSTRAINT fk_checkout_card FOREIGN KEY (CardID) REFERENCES PassengerCard(CardID),
    CONSTRAINT fk_checkout_station FOREIGN KEY (StationID) REFERENCES Station(StationID),
    CONSTRAINT fk_checkout_line FOREIGN KEY (LineID) REFERENCES Line(LineID),
    CONSTRAINT chk_fare CHECK (FareAmount > 0));


-------------------------------------------------------

--------------------- TRIGGERS ------------------------

-------- Trigger to validate travel document expiration or check bank card expiration date
-------- Purpose: Stop entry if the Bank Card or Ticket has expired.

CREATE OR REPLACE TRIGGER validate_travel_expiry
BEFORE INSERT ON CheckIn
FOR EACH ROW
DECLARE
    cardtype VARCHAR2(10);
    expirydate DATE;
BEGIN
    -- Identify the card type first
    SELECT CardType INTO cardtype
    FROM PassengerCard
    WHERE CardID = :NEW.CardID;
    
    -- For Bank Cards: Compare current time against ExpirationDate
    IF cardtype = 'BankCard' THEN
        SELECT ExpirationDate INTO expirydate
        FROM BankCard 
        WHERE CardID = :NEW.CardID;
        
        IF expirydate < :NEW.CheckInTime THEN
            RAISE_APPLICATION_ERROR(-20001, 'Access Denied: Bank Card has expired.');
        END IF;
        
    -- For Tickets: Compare current time against ValidUntil date
    ELSIF cardtype = 'Ticket' THEN
        SELECT ValidUntil INTO expirydate
        FROM Ticket 
        WHERE CardID = :NEW.CardID;
        
        IF expirydate < :NEW.CheckInTime THEN
            RAISE_APPLICATION_ERROR(-20002, 'Access Denied: Ticket validity period has ended.');
        END IF;
    END IF;
END;
/

-------- Trigger to enforce minimum balance requirements for Oyster users
-------- Purpose: Prevent Oyster users from starting a journey if they have zero or negative balance.

CREATE OR REPLACE TRIGGER prevent_negative_entry
BEFORE INSERT ON CheckIn
FOR EACH ROW
DECLARE
    cardtype VARCHAR2(10);
    balance NUMBER;
BEGIN
    -- Check the card type
    SELECT CardType INTO cardtype
    FROM PassengerCard
    WHERE CardID = :NEW.CardID;
    
    -- Check balance only for Oyster cards (Bank cards are authorized externally)
    IF cardtype = 'Oyster' THEN
        SELECT CreditAmount INTO balance
        FROM OysterCard 
        WHERE CardID = :NEW.CardID;
        
        -- Stop entry if balance is zero or negative
        IF balance <= 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Access Denied: Insufficient funds. Please top up.');
        END IF;
    END IF;
END;
/

--------- Trigger to update the main card balance after a journey completes
--------- Purpose: Update the Oyster card balance in the main table right after a checkout occurs.

CREATE OR REPLACE TRIGGER update_card_balance
AFTER INSERT ON CheckOut
FOR EACH ROW
-- Only trigger this update if a new credit value has been calculated
WHEN (NEW.NextCredit IS NOT NULL)
BEGIN
    -- Reflect the new balance in the main card registry
    UPDATE OysterCard
    SET CreditAmount = :NEW.NextCredit
    WHERE CardID = :NEW.CardID;
END;
/


-------------------------------------------------------------------------

---------------------------- INSERT DATA --------------------------------

------------------------ Stations ---------------------------

INSERT INTO Station VALUES ('S01', 'King''s Cross St Pancras', 'TRUE', 1);
INSERT INTO Station VALUES ('S02', 'Paddington', 'TRUE', 1);
INSERT INTO Station VALUES ('S03', 'Stratford', 'TRUE', 2);
INSERT INTO Station VALUES ('S04', 'Canary Wharf', 'TRUE', 2);
INSERT INTO Station VALUES ('S05', 'Richmond', 'FALSE', 4);
INSERT INTO Station VALUES ('S06', 'Wimbledon', 'TRUE', 3);
INSERT INTO Station VALUES ('S07', 'Ealing Broadway', 'TRUE', 3);
INSERT INTO Station VALUES ('S08', 'Bank', 'TRUE', 1);
INSERT INTO Station VALUES ('S09', 'Liverpool Street', 'TRUE', 1);
INSERT INTO Station VALUES ('S10', 'Westminster', 'TRUE', 1);
INSERT INTO Station VALUES ('S11', 'Greenwich', 'FALSE', 2);
INSERT INTO Station VALUES ('S12', 'Hammersmith', 'TRUE', 2);
INSERT INTO Station VALUES ('S13', 'Stanmore', 'TRUE', 5);
INSERT INTO Station VALUES ('S14', 'Heathrow Terminal 5', 'TRUE', 6);

----------------------- Lines -------------------------------

INSERT INTO Line VALUES ('L01', 'Central');
INSERT INTO Line VALUES ('L02', 'District');
INSERT INTO Line VALUES ('L03', 'Jubilee');
INSERT INTO Line VALUES ('L04', 'Northern');
INSERT INTO Line VALUES ('L05', 'DLR');
INSERT INTO Line VALUES ('L06', 'Elizabeth');
INSERT INTO Line VALUES ('L07', 'Piccadilly');
INSERT INTO Line VALUES ('L08', 'Victoria');

---------------------- Bank Holidays ----------------------------

INSERT INTO Holiday VALUES (TO_DATE('26-AUG-2024', 'DD-MON-YYYY'), 'Summer Bank Holiday');
INSERT INTO Holiday VALUES (TO_DATE('25-DEC-2024', 'DD-MON-YYYY'), 'Christmas Day');
INSERT INTO Holiday VALUES (TO_DATE('26-DEC-2024', 'DD-MON-YYYY'), 'Boxing Day');
INSERT INTO Holiday VALUES (TO_DATE('01-JAN-2025', 'DD-MON-YYYY'), 'New Year''s Day');

--------------------- PassengerCard -----------------------------

INSERT INTO PassengerCard VALUES ('OYS001', 'Oyster');
INSERT INTO PassengerCard VALUES ('OYS002', 'Oyster');
INSERT INTO PassengerCard VALUES ('OYS003', 'Oyster');
INSERT INTO PassengerCard VALUES ('OYS004', 'Oyster');
INSERT INTO PassengerCard VALUES ('OYS005', 'Oyster');
INSERT INTO PassengerCard VALUES ('OYS006', 'Oyster');
INSERT INTO PassengerCard VALUES ('4539012345678901', 'BankCard');
INSERT INTO PassengerCard VALUES ('4539087654321012', 'BankCard');
INSERT INTO PassengerCard VALUES ('4539111122223333', 'BankCard');
INSERT INTO PassengerCard VALUES ('4539444455556666', 'BankCard');
INSERT INTO PassengerCard VALUES ('4539777788889999', 'BankCard');
INSERT INTO PassengerCard VALUES ('TKT001', 'Ticket');
INSERT INTO PassengerCard VALUES ('TKT002', 'Ticket');
INSERT INTO PassengerCard VALUES ('TKT003', 'Ticket');
INSERT INTO PassengerCard VALUES ('TKT004', 'Ticket');

-------------------------- OysterCard (initial balances) --------------------

INSERT INTO OysterCard VALUES ('OYS001', 'John Smith', 50.00);
INSERT INTO OysterCard VALUES ('OYS002', NULL, 25.00);
INSERT INTO OysterCard VALUES ('OYS003', 'Emma Wilson', 80.00);
INSERT INTO OysterCard VALUES ('OYS004', NULL, 15.00);
INSERT INTO OysterCard VALUES ('OYS005', 'David Brown', 45.00);
INSERT INTO OysterCard VALUES ('OYS006', 'Sarah Jones', 35.00);

--------------------------- BankCard -----------------------------

INSERT INTO BankCard VALUES ('4539012345678901', 'Alice Brown', TO_DATE('31-AUG-2026', 'DD-MON-YYYY'));
INSERT INTO BankCard VALUES ('4539087654321012', 'Bob Johnson', TO_DATE('31-JAN-2025', 'DD-MON-YYYY'));
INSERT INTO BankCard VALUES ('4539111122223333', 'Charlie Davis', TO_DATE('15-MAR-2027', 'DD-MON-YYYY'));
INSERT INTO BankCard VALUES ('4539444455556666', 'Diana Miller', TO_DATE('20-MAY-2026', 'DD-MON-YYYY'));
INSERT INTO BankCard VALUES ('4539777788889999', 'Edward Wilson', TO_DATE('10-JAN-2028', 'DD-MON-YYYY'));

------------------------ Ticket ----------------------------------

INSERT INTO Ticket VALUES ('TKT001', TO_DATE('16-OCT-2024', 'DD-MON-YYYY'));
INSERT INTO Ticket VALUES ('TKT002', TO_DATE('26-DEC-2024', 'DD-MON-YYYY'));
INSERT INTO Ticket VALUES ('TKT003', TO_DATE('13-MAR-2025', 'DD-MON-YYYY'));
INSERT INTO Ticket VALUES ('TKT004', TO_DATE('23-OCT-2025', 'DD-MON-YYYY'));

------------- StationLine (which lines stop at which stations) -----------------

-- King's Cross: Northern, Piccadilly, Victoria
INSERT INTO StationLine VALUES ('S01', 'L04');
INSERT INTO StationLine VALUES ('S01', 'L07');
INSERT INTO StationLine VALUES ('S01', 'L08');
-- Paddington: District, Elizabeth
INSERT INTO StationLine VALUES ('S02', 'L02');
INSERT INTO StationLine VALUES ('S02', 'L06');
-- Stratford: Central, Jubilee, DLR, Elizabeth
INSERT INTO StationLine VALUES ('S03', 'L01');
INSERT INTO StationLine VALUES ('S03', 'L03');
INSERT INTO StationLine VALUES ('S03', 'L05');
INSERT INTO StationLine VALUES ('S03', 'L06');
-- Canary Wharf: Jubilee, DLR, Elizabeth
INSERT INTO StationLine VALUES ('S04', 'L03');
INSERT INTO StationLine VALUES ('S04', 'L05');
INSERT INTO StationLine VALUES ('S04', 'L06');
-- Richmond: District only
INSERT INTO StationLine VALUES ('S05', 'L02');
-- Wimbledon: District only
INSERT INTO StationLine VALUES ('S06', 'L02');
-- Ealing Broadway: Central, District, Elizabeth
INSERT INTO StationLine VALUES ('S07', 'L01');
INSERT INTO StationLine VALUES ('S07', 'L02');
INSERT INTO StationLine VALUES ('S07', 'L06');
-- Bank: Central, Northern, DLR
INSERT INTO StationLine VALUES ('S08', 'L01');
INSERT INTO StationLine VALUES ('S08', 'L04');
INSERT INTO StationLine VALUES ('S08', 'L05');
-- Liverpool Street: Central, Elizabeth
INSERT INTO StationLine VALUES ('S09', 'L01');
INSERT INTO StationLine VALUES ('S09', 'L06');
-- Westminster: District, Jubilee
INSERT INTO StationLine VALUES ('S10', 'L02');
INSERT INTO StationLine VALUES ('S10', 'L03');
-- Greenwich: DLR only
INSERT INTO StationLine VALUES ('S11', 'L05');
-- Hammersmith: District, Piccadilly
INSERT INTO StationLine VALUES ('S12', 'L02');
INSERT INTO StationLine VALUES ('S12', 'L07');
-- Stanmore: Jubilee
INSERT INTO StationLine VALUES ('S13', 'L03');
-- Heathrow Terminal 5: Piccadilly
INSERT INTO StationLine VALUES ('S14', 'L07');


------------------- CheckIn ---------------------

-- Holidays - Summer Bank Holiday, Christmas, Boxing Day, and New Year's Day
INSERT INTO CheckIn VALUES ('CI001', 'OYS001', 'S01', 'L04', TO_DATE('26-AUG-2024 08:17', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI001B', 'OYS001', 'S08', 'L05', TO_DATE('26-AUG-2024 08:55', 'DD-MON-YYYY HH24:MI'), 'PinkReader');
INSERT INTO CheckIn VALUES ('CI002', 'OYS002', 'S03', 'L03', TO_DATE('26-AUG-2024 09:23', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI003', '4539012345678901', 'S08', 'L01', TO_DATE('26-AUG-2024 10:08', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI014', 'OYS003', 'S01', 'L08', TO_DATE('25-DEC-2024 09:11', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI015', 'OYS004', 'S08', 'L04', TO_DATE('25-DEC-2024 10:38', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI016', '4539777788889999', 'S03', 'L06', TO_DATE('25-DEC-2024 11:02', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI017', 'TKT002', 'S02', 'L06', TO_DATE('25-DEC-2024 12:24', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI018', 'OYS005', 'S04', 'L03', TO_DATE('26-DEC-2024 08:09', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI019', 'OYS006', 'S09', 'L01', TO_DATE('26-DEC-2024 09:16', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI020', '4539012345678901', 'S10', 'L02', TO_DATE('26-DEC-2024 10:41', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI021', 'OYS001', 'S06', 'L02', TO_DATE('01-JAN-2025 11:07', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI022', 'OYS002', 'S03', 'L06', TO_DATE('01-JAN-2025 12:18', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI023', '4539087654321012', 'S12', 'L07', TO_DATE('01-JAN-2025 13:29', 'DD-MON-YYYY HH24:MI'), 'Standard');

-- Standard Daily Commutes
INSERT INTO CheckIn VALUES ('CI004', 'OYS003', 'S02', 'L02', TO_DATE('15-OCT-2024 07:42', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI004B', 'OYS004', 'S09', 'L06', TO_DATE('15-OCT-2024 08:00', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI005', 'OYS004', 'S04', 'L05', TO_DATE('15-OCT-2024 08:31', 'DD-MON-YYYY HH24:MI'), 'PinkReader');
INSERT INTO CheckIn VALUES ('CI006', '4539087654321012', 'S09', 'L06', TO_DATE('15-OCT-2024 09:05', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI007', 'TKT001', 'S06', 'L02', TO_DATE('15-OCT-2024 14:12', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI008', 'OYS005', 'S01', 'L07', TO_DATE('16-OCT-2024 08:03', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI009', 'OYS006', 'S12', 'L02', TO_DATE('16-OCT-2024 09:27', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI010', '4539111122223333', 'S10', 'L03', TO_DATE('16-OCT-2024 11:14', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI011', 'OYS001', 'S05', 'L02', TO_DATE('17-OCT-2024 10:06', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI012', '4539444455556666', 'S07', 'L01', TO_DATE('17-OCT-2024 12:19', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI013', 'OYS002', 'S11', 'L05', TO_DATE('17-OCT-2024 15:33', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI024', 'OYS003', 'S08', 'L05', TO_DATE('10-MAR-2025 07:36', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI024B', 'OYS004', 'S02', 'L06', TO_DATE('10-MAR-2025 08:10', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI025', 'OYS004', 'S03', 'L01', TO_DATE('10-MAR-2025 08:47', 'DD-MON-YYYY HH24:MI'), 'PinkReader');
INSERT INTO CheckIn VALUES ('CI026', '4539111122223333', 'S02', 'L02', TO_DATE('10-MAR-2025 09:21', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI027', 'TKT003', 'S04', 'L05', TO_DATE('11-MAR-2025 10:04', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI028', 'OYS005', 'S09', 'L06', TO_DATE('11-MAR-2025 11:38', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI029', 'OYS006', 'S05', 'L02', TO_DATE('12-MAR-2025 08:13', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI030', '4539444455556666', 'S01', 'L04', TO_DATE('12-MAR-2025 09:26', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI031', 'OYS006', 'S02', 'L02', TO_DATE('17-MAR-2025 17:45', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI032', 'OYS002', 'S01', 'L04', TO_DATE('17-MAR-2025 18:15', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI033', 'OYS004', 'S09', 'L01', TO_DATE('17-MAR-2025 19:30', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI034', 'OYS001', 'S13', 'L03', TO_DATE('18-MAR-2025 08:20', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI035', 'OYS003', 'S14', 'L07', TO_DATE('18-MAR-2025 14:00', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI041', 'OYS003', 'S01', 'L07', TO_DATE('18-MAR-2025 18:30', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI042', 'OYS001', 'S01', 'L03', TO_DATE('18-MAR-2025 17:30', 'DD-MON-YYYY HH24:MI'), 'Standard');

-- Anomalies: Incomplete Journeys (Missing Check-Outs)
-- Used to test 'Incomplete Journey' detection queries
INSERT INTO CheckIn VALUES ('CI036', 'OYS001', 'S07', 'L02', TO_DATE('05-JUN-2025 08:34', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI037', 'OYS002', 'S10', 'L03', TO_DATE('05-JUN-2025 10:22', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI038', '4539777788889999', 'S11', 'L05', TO_DATE('06-JUN-2025 09:07', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI039', 'OYS003', 'S12', 'L07', TO_DATE('06-JUN-2025 14:19', 'DD-MON-YYYY HH24:MI'), 'Standard');
INSERT INTO CheckIn VALUES ('CI040', 'TKT004', 'S03', 'L03', TO_DATE('21-OCT-2025 10:41', 'DD-MON-YYYY HH24:MI'), 'Standard');


------------- CheckOut --------------------------

-- Holidays - Summer Bank Holiday, Christmas, Boxing Day, and New Year's Day
INSERT INTO CheckOut VALUES ('CO001', 'OYS001', 'S11', 'L05', TO_DATE('26-AUG-2024 09:20', 'DD-MON-YYYY HH24:MI'), 5.40, 50.00, 44.60);
INSERT INTO CheckOut VALUES ('CO002', 'OYS002', 'S04', 'L03', TO_DATE('26-AUG-2024 09:58', 'DD-MON-YYYY HH24:MI'), 2.70, 25.00, 22.30);
INSERT INTO CheckOut VALUES ('CO003', '4539012345678901', 'S10', 'L02', TO_DATE('26-AUG-2024 10:43', 'DD-MON-YYYY HH24:MI'), 2.70, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO014', 'OYS003', 'S10', 'L02', TO_DATE('25-DEC-2024 09:48', 'DD-MON-YYYY HH24:MI'), 2.70, 76.10, 73.40);
INSERT INTO CheckOut VALUES ('CO015', 'OYS004', 'S01', 'L04', TO_DATE('25-DEC-2024 11:23', 'DD-MON-YYYY HH24:MI'), 2.70, 9.60, 6.90);
INSERT INTO CheckOut VALUES ('CO016', '4539777788889999', 'S09', 'L06', TO_DATE('25-DEC-2024 11:49', 'DD-MON-YYYY HH24:MI'), 3.00, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO017', 'TKT002', 'S03', 'L06', TO_DATE('25-DEC-2024 12:58', 'DD-MON-YYYY HH24:MI'), 3.00, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO018', 'OYS005', 'S11', 'L05', TO_DATE('26-DEC-2024 08:46', 'DD-MON-YYYY HH24:MI'), 2.70, 42.20, 39.50);
INSERT INTO CheckOut VALUES ('CO019', 'OYS006', 'S08', 'L01', TO_DATE('26-DEC-2024 09:53', 'DD-MON-YYYY HH24:MI'), 2.70, 32.00, 29.30);
INSERT INTO CheckOut VALUES ('CO020', '4539012345678901', 'S12', 'L02', TO_DATE('26-DEC-2024 11:27', 'DD-MON-YYYY HH24:MI'), 3.00, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO021', 'OYS001', 'S02', 'L02', TO_DATE('01-JAN-2025 11:52', 'DD-MON-YYYY HH24:MI'), 3.50, 41.10, 37.60);
INSERT INTO CheckOut VALUES ('CO022', 'OYS002', 'S04', 'L06', TO_DATE('01-JAN-2025 12:54', 'DD-MON-YYYY HH24:MI'), 2.70, 19.60, 16.90);
INSERT INTO CheckOut VALUES ('CO023', '4539087654321012', 'S01', 'L07', TO_DATE('01-JAN-2025 14:06', 'DD-MON-YYYY HH24:MI'), 3.00, NULL, NULL);

-- Standard Daily Commutes
INSERT INTO CheckOut VALUES ('CO004', 'OYS003', 'S06', 'L02', TO_DATE('15-OCT-2024 08:28', 'DD-MON-YYYY HH24:MI'), 3.90, 80.00, 76.10);
INSERT INTO CheckOut VALUES ('CO005', 'OYS004', 'S08', 'L05', TO_DATE('15-OCT-2024 09:14', 'DD-MON-YYYY HH24:MI'), 5.40, 15.00, 9.60);
INSERT INTO CheckOut VALUES ('CO006', '4539087654321012', 'S03', 'L06', TO_DATE('15-OCT-2024 09:51', 'DD-MON-YYYY HH24:MI'), 3.40, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO007', 'TKT001', 'S02', 'L02', TO_DATE('15-OCT-2024 15:03', 'DD-MON-YYYY HH24:MI'), 3.90, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO008', 'OYS005', 'S10', 'L03', TO_DATE('16-OCT-2024 08:47', 'DD-MON-YYYY HH24:MI'), 2.80, 45.00, 42.20);
INSERT INTO CheckOut VALUES ('CO009', 'OYS006', 'S06', 'L02', TO_DATE('16-OCT-2024 10:18', 'DD-MON-YYYY HH24:MI'), 3.00, 35.00, 32.00);
INSERT INTO CheckOut VALUES ('CO010', '4539111122223333', 'S04', 'L03', TO_DATE('16-OCT-2024 11:51', 'DD-MON-YYYY HH24:MI'), 3.40, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO011', 'OYS001', 'S07', 'L02', TO_DATE('17-OCT-2024 10:49', 'DD-MON-YYYY HH24:MI'), 3.50, 44.60, 41.10);
INSERT INTO CheckOut VALUES ('CO012', '4539444455556666', 'S08', 'L01', TO_DATE('17-OCT-2024 12:57', 'DD-MON-YYYY HH24:MI'), 3.90, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO013', 'OYS002', 'S04', 'L05', TO_DATE('17-OCT-2024 16:08', 'DD-MON-YYYY HH24:MI'), 2.70, 22.30, 19.60);
INSERT INTO CheckOut VALUES ('CO024', 'OYS003', 'S04', 'L05', TO_DATE('10-MAR-2025 08:19', 'DD-MON-YYYY HH24:MI'), 3.40, 73.40, 70.00);
INSERT INTO CheckOut VALUES ('CO025', 'OYS004', 'S09', 'L01', TO_DATE('10-MAR-2025 09:32', 'DD-MON-YYYY HH24:MI'), 5.40, 6.90, 1.50);
INSERT INTO CheckOut VALUES ('CO026', '4539111122223333', 'S05', 'L02', TO_DATE('10-MAR-2025 10:13', 'DD-MON-YYYY HH24:MI'), 4.70, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO027', 'TKT003', 'S11', 'L05', TO_DATE('11-MAR-2025 10:47', 'DD-MON-YYYY HH24:MI'), 2.80, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO028', 'OYS005', 'S03', 'L06', TO_DATE('11-MAR-2025 12:21', 'DD-MON-YYYY HH24:MI'), 3.40, 39.50, 36.10);
INSERT INTO CheckOut VALUES ('CO029', 'OYS006', 'S12', 'L02', TO_DATE('12-MAR-2025 08:51', 'DD-MON-YYYY HH24:MI'), 3.50, 29.30, 25.80);
INSERT INTO CheckOut VALUES ('CO030', '4539444455556666', 'S10', 'L03', TO_DATE('12-MAR-2025 09:58', 'DD-MON-YYYY HH24:MI'), 2.80, NULL, NULL);
INSERT INTO CheckOut VALUES ('CO031', 'OYS006', 'S06', 'L02', TO_DATE('17-MAR-2025 18:30', 'DD-MON-YYYY HH24:MI'), 3.00, 25.80, 22.80);
INSERT INTO CheckOut VALUES ('CO032', 'OYS002', 'S08', 'L04', TO_DATE('17-MAR-2025 18:52', 'DD-MON-YYYY HH24:MI'), 2.80, 16.90, 14.10);
INSERT INTO CheckOut VALUES ('CO033', 'OYS004', 'S07', 'L01', TO_DATE('17-MAR-2025 20:10', 'DD-MON-YYYY HH24:MI'), 1.50, 1.50, 0.00);
INSERT INTO CheckOut VALUES ('CO034', 'OYS001', 'S01', 'L03', TO_DATE('18-MAR-2025 09:10', 'DD-MON-YYYY HH24:MI'), 6.50, 37.60, 31.10);
INSERT INTO CheckOut VALUES ('CO035', 'OYS003', 'S01', 'L07', TO_DATE('18-MAR-2025 15:20', 'DD-MON-YYYY HH24:MI'), 6.70, 70.00, 63.30);
INSERT INTO CheckOut VALUES ('CO039', 'OYS003', 'S14', 'L07', TO_DATE('18-MAR-2025 19:45', 'DD-MON-YYYY HH24:MI'), 5.60, 63.30, 57.70);
INSERT INTO CheckOut VALUES ('CO040', 'OYS001', 'S13', 'L03', TO_DATE('18-MAR-2025 18:15', 'DD-MON-YYYY HH24:MI'), 5.10, 31.10, 26.00);

-- Anomalies: Incomplete Journeys (Missing Check-Ins)
INSERT INTO CheckOut VALUES ('CO036', 'OYS001', 'S08', 'L04', TO_DATE('20-JUN-2025 09:17', 'DD-MON-YYYY HH24:MI'), 8.60, 26.00, 17.40);
INSERT INTO CheckOut VALUES ('CO037', 'OYS005', 'S01', 'L04', TO_DATE('22-JUN-2025 18:34', 'DD-MON-YYYY HH24:MI'), 8.60, 36.10, 27.50);
INSERT INTO CheckOut VALUES ('CO038', '4539012345678901', 'S10', 'L02', TO_DATE('25-JUN-2025 14:22', 'DD-MON-YYYY HH24:MI'), 8.60, NULL, NULL);


COMMIT;



--------------------------------------------------------

---------------------- VIEWS ---------------------------

-- View 1: View total fares collected for each line

CREATE OR REPLACE VIEW LineFaresSummary AS
SELECT l.LineID, l.LineName, COUNT(*) AS JourneyCount, SUM(co.FareAmount) AS TotalFares
FROM CheckOut co
JOIN Line l ON co.LineID = l.LineID
GROUP BY l.LineID, l.LineName
ORDER BY TotalFares DESC;

-- View 2: View zone-based revenue summary with total check-out

CREATE OR REPLACE VIEW ZoneRevenueSummary AS
SELECT s.Zone, COUNT(co.CheckOutID) AS TotalCheckOuts, SUM(co.FareAmount) AS TotalRevenue, ROUND(AVG(co.FareAmount), 2) AS AverageFare
FROM Station s
LEFT JOIN CheckOut co ON s.StationID = co.StationID
GROUP BY s.Zone
ORDER BY s.Zone;

-- View 3: View incomplete journeys where passengers checked in but never checked out

CREATE OR REPLACE VIEW IncompleteJourneys AS
SELECT ci.CheckInID, ci.CardID, pc.CardType, ci.StationID, s.StationName, ci.LineID, l.LineName, ci.CheckInTime, ci.CheckInType
FROM CheckIn ci
JOIN PassengerCard pc ON ci.CardID = pc.CardID
JOIN Station s ON ci.StationID = s.StationID
JOIN Line l ON ci.LineID = l.LineID
WHERE NOT EXISTS (SELECT * 
                  FROM CheckOut co 
                  WHERE co.CardID = ci.CardID 
                  AND co.CheckOutTime > ci.CheckInTime);

-- View 4: View station activity with total check-in and check-out counts

CREATE OR REPLACE VIEW StationActivity AS
SELECT s.StationID, s.StationName, s.Zone, 
       CASE WHEN s.HasBarrier = 'TRUE' THEN 'Yes' ELSE 'No' END AS HasBarrier,
       COUNT(DISTINCT ci.CheckInID) AS TotalCheckIns,
       COUNT(DISTINCT co.CheckOutID) AS TotalCheckOuts
FROM Station s
LEFT JOIN CheckIn ci ON s.StationID = ci.StationID
LEFT JOIN CheckOut co ON s.StationID = co.StationID
GROUP BY s.StationID, s.StationName, s.Zone, s.HasBarrier
ORDER BY COUNT(DISTINCT ci.CheckInID) DESC;



---------------------------------------------------------

--------------------- QUERIES ---------------------------

-- Query 1: List all stations on the Northern line

SELECT s.StationID, s.StationName, s.Zone
FROM Station s
JOIN StationLine sl ON s.StationID = sl.StationID
JOIN Line l ON sl.LineID = l.LineID
WHERE l.LineName = 'Northern'
ORDER BY s.Zone, s.StationName;

-- Query 2: Find all expired bank cards and tickets

SELECT CardID, CardHolderName, ExpirationDate, 'BankCard' AS CardType
FROM BankCard
WHERE ExpirationDate < SYSDATE
UNION
SELECT CardID, '-', ValidUntil, 'Ticket' AS CardType
FROM Ticket
WHERE ValidUntil < SYSDATE;

-- Query 3: Calculate the total fares collected for each line

SELECT l.LineID, l.LineName, SUM(co.FareAmount) AS TotalFares
FROM CheckOut co
JOIN Line l ON co.LineID = l.LineID
GROUP BY l.LineID, l.LineName
ORDER BY TotalFares DESC;

-- Query 4: Calculate the average fare for each passenger card type

SELECT pc.CardType, COUNT(*) AS JourneyCount, ROUND(AVG(co.FareAmount), 2) AS AverageFare
FROM CheckOut co
JOIN PassengerCard pc ON co.CardID = pc.CardID
GROUP BY pc.CardType
ORDER BY AverageFare DESC;

-- Query 5: Count the number of journeys made on public holidays

SELECT TO_CHAR(h.HolidayDate, 'DD-MON-YYYY') AS HolidayDate, h.HolidayName, COUNT(*) AS JourneyCount
FROM Holiday h
JOIN CheckOut co ON TRUNC(co.CheckOutTime) = h.HolidayDate
GROUP BY h.HolidayDate, h.HolidayName
ORDER BY h.HolidayDate;

-- Query 6: Count the number of check-ins for each hour range throughout the day

SELECT TO_CHAR(CheckInTime, 'HH24') || ':00 - ' || TO_CHAR(CheckInTime, 'HH24') || ':59' AS HourRange, COUNT(*) AS CheckInCount
FROM CheckIn
GROUP BY TO_CHAR(CheckInTime, 'HH24')
ORDER BY CheckInCount DESC;

-- Query 7: Find passengers with more than 3 completed journeys

SELECT co.CardID, pc.CardType, COUNT(*) AS JourneyCount
FROM CheckOut co
JOIN PassengerCard pc ON co.CardID = pc.CardID
GROUP BY co.CardID, pc.CardType
HAVING COUNT(*) > 3
ORDER BY JourneyCount DESC;

-- Query 8: Find pink reader usage to identify popular transit stations and line changes

SELECT s.StationName, s.Zone, l.LineName AS ConnectedLine, COUNT(*) AS PinkReaderUsageCount
FROM CheckIn ci
JOIN Station s ON ci.StationID = s.StationID
JOIN Line l ON ci.LineID = l.LineID
WHERE ci.CheckInType = 'PinkReader'
GROUP BY s.StationName, s.Zone, l.LineName
ORDER BY PinkReaderUsageCount DESC;

-- Query 9: Find the details of the most expensive journey

SELECT co.CheckOutID, co.CardID, pc.CardType, s.StationName, l.LineName, TO_CHAR(co.CheckOutTime, 'DD-MON-YYYY HH24:MI') AS CheckOutTime, co.FareAmount
FROM CheckOut co
JOIN PassengerCard pc ON co.CardID = pc.CardID
JOIN Station s ON co.StationID = s.StationID
JOIN Line l ON co.LineID = l.LineID
ORDER BY co.FareAmount DESC
FETCH FIRST 1 ROW ONLY;

-- Query 10: Find the station with the highest total activity (check-ins and check-outs)

SELECT s.StationID, s.StationName, s.Zone, COUNT(DISTINCT ci.CheckInID) + COUNT(DISTINCT co.CheckOutID) AS TotalActivity
FROM Station s
LEFT JOIN CheckIn ci ON s.StationID = ci.StationID
LEFT JOIN CheckOut co ON s.StationID = co.StationID
GROUP BY s.StationID, s.StationName, s.Zone
ORDER BY TotalActivity DESC
FETCH FIRST 1 ROW ONLY;

-- Query 11: Find all passengers that have at least one incomplete journey

SELECT DISTINCT pc.CardID, pc.CardType
FROM PassengerCard pc
WHERE EXISTS (SELECT * FROM CheckIn ci 
              WHERE ci.CardID = pc.CardID
              AND NOT EXISTS (SELECT * FROM CheckOut co
                              WHERE co.CardID = ci.CardID
                              AND co.CheckOutTime > ci.CheckInTime));

-- Query 12: Identify the most frequently travelled routes between stations

SELECT s1.StationName || ' ➜ ' || s2.StationName AS Route, l.LineName, COUNT(*) AS TotalJourneys
FROM CheckIn ci
JOIN CheckOut co ON ci.CardID = co.CardID AND co.CheckOutTime > ci.CheckInTime AND TRUNC(co.CheckOutTime) = TRUNC(ci.CheckInTime)
JOIN Station s1 ON ci.StationID = s1.StationID
JOIN Station s2 ON co.StationID = s2.StationID
JOIN Line l ON ci.LineID = l.LineID
GROUP BY s1.StationName, s2.StationName, l.LineName
HAVING COUNT(*) > 1
ORDER BY TotalJourneys DESC;

