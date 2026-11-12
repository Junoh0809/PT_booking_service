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
    FOREIGN KEY (trainer_id) REFERENCES trainer(id)
);

-- 구매 전에도 선택할 수 있는 이용권 종류입니다.
CREATE TABLE ticket_type (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL UNIQUE,
    price INT NOT NULL CHECK (price >= 0),
    total_count INT NOT NULL CHECK (total_count > 0)
);

CREATE TABLE ticket (
    id INT PRIMARY KEY AUTO_INCREMENT,
    member_id INT NOT NULL,
    ticket_type_id INT NOT NULL,
    -- 구매 시점의 가격·횟수를 보존합니다. 종류의 가격이 바뀌어도 과거 구매 내역은 유지됩니다.
    price INT NOT NULL CHECK ( price >= 0 ),
    total_count INT NOT NULL CHECK ( total_count > 0 ),
    remaining_count INT NOT NULL, # 남은 횟수
    start_date DATE NOT NULL,   # 이용권 시작일자
    expire_date DATE GENERATED ALWAYS AS (DATE_ADD( start_date
        , INTERVAL 1 YEAR)) STORED NOT NULL,  # 이용권 만료일
    CONSTRAINT ticket_remaining_count_chk
        CHECK (remaining_count BETWEEN 0 AND total_count),
    FOREIGN KEY (member_id) REFERENCES member(id),
    FOREIGN KEY (ticket_type_id) REFERENCES ticket_type(id)
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
    FOREIGN KEY (class_session_id) REFERENCES class_session(id),
    FOREIGN KEY (ticket_id) REFERENCES ticket(id)
);

-- 애플리케이션 계정에는 이 역할만 부여합니다. 계정 생성과 역할 지정은 배포 환경에서 수행합니다.
-- 예약/이용권 횟수/결제의 원자적 변경은 objects.sql의 프로시저가 담당합니다.
CREATE ROLE IF NOT EXISTS 'pt_booking_app';
GRANT EXECUTE ON pt_booking.* TO 'pt_booking_app';
