-- 새 pt_booking 데이터베이스에 적용할 전체 스키마입니다.
-- 기존 데이터가 있는 DB에는 CREATE TABLE이 실패하므로 마이그레이션 용도로 사용하지 않습니다.
CREATE DATABASE IF NOT EXISTS pt_booking;
USE pt_booking;

CREATE TABLE member (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(10) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    birth_day DATE NOT NULL,
    create_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trainer (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(10) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    birth_day DATE NOT NULL,
    create_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hire_date DATE NOT NULL
);

CREATE TABLE class_session (
    id INT PRIMARY KEY AUTO_INCREMENT,
    trainer_id INT NOT NULL,
    start_at DATETIME NOT NULL,
    end_at DATETIME NOT NULL,
    max_members INT NOT NULL CHECK (max_members > 0),
    status VARCHAR(10) NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'CLOSE')),
    CONSTRAINT class_session_time_chk CHECK (end_at > start_at),
    KEY idx_class_session_trainer_time (trainer_id, start_at, end_at),
    FOREIGN KEY (trainer_id) REFERENCES trainer(id)
);

CREATE TABLE ticket (
    id INT PRIMARY KEY AUTO_INCREMENT,
    member_id INT NOT NULL,
    price INT NOT NULL CHECK ( price >= 0 ),
    total_count INT NOT NULL CHECK ( total_count > 0 ),
    remaining_count INT NOT NULL, # 남은 횟수
    start_date DATE NOT NULL,   # 이용권 시작일자
    expire_date DATE GENERATED ALWAYS AS (DATE_ADD( start_date
        , INTERVAL 1 YEAR)) STORED NOT NULL,  # 이용권 만료일
    CONSTRAINT ticket_remaining_count_chk
        CHECK (remaining_count BETWEEN 0 AND total_count),
    FOREIGN KEY (member_id) REFERENCES member(id)
);

CREATE TABLE payment (
    id INT PRIMARY KEY AUTO_INCREMENT,
    ticket_id INT NOT NULL,
    paid_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, # 결제일시
    UNIQUE(ticket_id),
    FOREIGN KEY (ticket_id) REFERENCES ticket(id)
);

CREATE TABLE reservation (
    id INT PRIMARY KEY AUTO_INCREMENT,
    class_session_id INT NOT NULL,
    ticket_id INT NOT NULL,
    create_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    canceled_at DATETIME NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
        CHECK (status IN ('RESERVED', 'CANCELED', 'DONE', 'NO_SHOW')),
    CONSTRAINT chk_reservation_cancellation CHECK (
        (status = 'CANCELED'
            AND canceled_at IS NOT NULL
            AND canceled_at >= create_at)
        OR (status <> 'CANCELED' AND canceled_at IS NULL)
    ),
    KEY idx_reservation_class_status (class_session_id, status),
    FOREIGN KEY (class_session_id) REFERENCES class_session(id),
    FOREIGN KEY (ticket_id) REFERENCES ticket(id)
);

DELIMITER //

-- 새 수업을 OPEN으로 시작하고, 같은 트레이너의 수업 시간 중복을 막습니다.
CREATE TRIGGER class_session_overlap_insert
BEFORE INSERT ON class_session FOR EACH ROW
BEGIN
    DECLARE v_trainer_id INT;

    SELECT id INTO v_trainer_id
    FROM trainer WHERE id = NEW.trainer_id FOR UPDATE;

    IF NEW.status <> 'OPEN' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '새 수업은 OPEN이어야 합니다.';ㅂ
    END IF;

    IF EXISTS (
        SELECT 1 FROM class_session
        WHERE trainer_id = NEW.trainer_id
          AND NEW.start_at < end_at AND NEW.end_at > start_at
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '트레이너의 수업 시간이 겹칩니다.';
    END IF;
END //

-- 예약이 있는 수업의 일정·트레이너 변경과 예약 인원에 맞지 않는 정원·상태 변경을 막습니다.
CREATE TRIGGER class_session_time_change_guard
BEFORE UPDATE ON class_session FOR EACH ROW
BEGIN
    DECLARE v_trainer_id INT;
    DECLARE v_used_count INT;

    IF NEW.trainer_id <> OLD.trainer_id
       OR NEW.start_at <> OLD.start_at
       OR NEW.end_at <> OLD.end_at THEN
        SELECT id INTO v_trainer_id
        FROM trainer WHERE id = NEW.trainer_id FOR UPDATE;

        IF EXISTS (
            SELECT 1 FROM reservation
            WHERE class_session_id = OLD.id AND status <> 'CANCELED'
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '예약이 있는 수업의 시간이나 트레이너는 변경할 수 없습니다.';
        END IF;

        IF EXISTS (
            SELECT 1 FROM class_session
            WHERE trainer_id = NEW.trainer_id AND id <> OLD.id
              AND NEW.start_at < end_at AND NEW.end_at > start_at
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '트레이너의 수업 시간이 겹칩니다.';
        END IF;
    END IF;

    SELECT COUNT(*) INTO v_used_count
    FROM reservation
    WHERE class_session_id = OLD.id AND status <> 'CANCELED';

    IF NEW.max_members < v_used_count
       OR (v_used_count < NEW.max_members AND NEW.status <> 'OPEN')
       OR (v_used_count = NEW.max_members AND NEW.status <> 'CLOSE') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '수업 정원과 상태가 예약 수에 맞지 않습니다.';
    END IF;
END //

-- 이용권이 달라도 같은 회원의 수업 시간이 겹치는 예약을 막습니다.
CREATE TRIGGER reservation_member_overlap_insert
BEFORE INSERT ON reservation FOR EACH ROW
BEGIN
    DECLARE v_member_id INT;
    DECLARE v_locked_member_id INT;
    DECLARE v_start_at DATETIME;
    DECLARE v_end_at DATETIME;

    IF NEW.status <> 'RESERVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '새 예약은 RESERVED여야 합니다.';
    END IF;

    SELECT member_id INTO v_member_id
    FROM ticket WHERE id = NEW.ticket_id;

    SELECT id INTO v_locked_member_id
    FROM member WHERE id = v_member_id FOR UPDATE;

    SELECT start_at, end_at INTO v_start_at, v_end_at
    FROM class_session WHERE id = NEW.class_session_id;

    IF EXISTS (
        SELECT 1 FROM reservation r
        JOIN ticket t ON t.id = r.ticket_id
        JOIN class_session c ON c.id = r.class_session_id
        WHERE t.member_id = v_member_id AND r.status <> 'CANCELED'
          AND c.start_at < v_end_at AND c.end_at > v_start_at
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '회원의 예약 시간이 겹칩니다.';
    END IF;
END //

-- 예약의 수업·이용권 교체와 취소·완료·노쇼 처리 후 상태 재변경을 막습니다.
CREATE TRIGGER reservation_identity_guard
BEFORE UPDATE ON reservation FOR EACH ROW
BEGIN
    IF NEW.class_session_id <> OLD.class_session_id
       OR NEW.ticket_id <> OLD.ticket_id
       OR (OLD.status <> 'RESERVED' AND NEW.status <> OLD.status) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '예약의 수업, 이용권 또는 확정된 상태를 변경할 수 없습니다.';
    END IF;
END //

DELIMITER ;

-- 애플리케이션 계정에는 이 역할만 부여합니다. 계정 생성과 역할 지정은 배포 환경에서 수행합니다.
-- 예약/이용권 횟수/결제의 원자적 변경은 PT_Booking_Procedures.sql의 프로시저가 담당합니다.
CREATE ROLE IF NOT EXISTS 'pt_booking_app';
GRANT EXECUTE ON pt_booking.* TO 'pt_booking_app';
