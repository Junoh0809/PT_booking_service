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
    end_at DATETIME NOT NULL CHECK (end_at > start_at),
    max_members INT NOT NULL CHECK (max_members > 0),
    status VARCHAR(10) NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'CLOSE')),
    FOREIGN KEY (trainer_id) REFERENCES trainer(id)
);

CREATE TABLE ticket (
    id INT PRIMARY KEY AUTO_INCREMENT,
    member_id INT NOT NULL,
    price INT NOT NULL CHECK ( price >= 0 ),
    total_count INT NOT NULL CHECK ( total_count > 0 ),
    remaining_count INT NOT NULL CHECK ( remaining_count BETWEEN 0 AND total_count), # 남은 횟수
    start_date DATE NOT NULL,   # 이용권 시작일자
    expire_date DATE GENERATED ALWAYS AS (DATE_ADD(start_date, INTERVAL 1 YEAR)) STORED NOT NULL,  # 이용권 만료일
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
    FOREIGN KEY (class_session_id) REFERENCES class_session(id),
    FOREIGN KEY (ticket_id) REFERENCES ticket(id)
);
