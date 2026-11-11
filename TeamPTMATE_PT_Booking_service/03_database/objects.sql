USE pt_booking;

DELIMITER //

DROP PROCEDURE IF EXISTS register_member //

CREATE PROCEDURE register_member(
    IN p_name VARCHAR(10),
    IN p_phone VARCHAR(20),
    IN p_birth_day DATE
)
BEGIN
    INSERT INTO member (name, phone, birth_day)
    VALUES (p_name, p_phone, p_birth_day);

    SELECT id, name, phone, birth_day, create_at
    FROM member
    WHERE id = LAST_INSERT_ID();
END //

DELIMITER ;

-- F-02 회원 조회 기능 (명세서 기준 수정)

DELIMITER //

DROP PROCEDURE IF EXISTS search_member //

CREATE PROCEDURE search_member(
    IN p_id INT
)
BEGIN
    SELECT
        id,
        name,
        phone,
        birth_day,
        create_at
    FROM member
    WHERE id = p_id;
END //

DELIMITER ;

-- F-03 트레이너 등록 기능

DELIMITER //

DROP PROCEDURE IF EXISTS register_trainer //

CREATE PROCEDURE register_trainer(
    IN p_name VARCHAR(10),
    IN p_phone VARCHAR(20),
    IN p_birth_day DATE,
    IN p_hire_date DATE
)
BEGIN
    INSERT INTO trainer (name, phone, birth_day, hire_date)
    VALUES (p_name, p_phone, p_birth_day, p_hire_date);

    SELECT id, name, phone, birth_day, hire_date, create_at
    FROM trainer
    WHERE id = LAST_INSERT_ID();
END //

DELIMITER ;

-- F-04 트레이너 조회 (명세서 기준 수정)

DELIMITER //

DROP PROCEDURE IF EXISTS search_trainer //

CREATE PROCEDURE search_trainer(
    IN p_id INT
)
BEGIN
    SELECT
        id,
        name,
        phone,
        birth_day,
        hire_date,
        create_at
    FROM trainer
    WHERE id = p_id;
END //

DELIMITER ;

-- F-05 수강권 구매 및 결제 기능

DELIMITER //

DROP PROCEDURE IF EXISTS purchase_ticket //

CREATE PROCEDURE purchase_ticket(
    IN p_member_id INT,
    IN p_price INT,
    IN p_total_count INT,
    IN p_start_date DATE
)
BEGIN
    DECLARE v_ticket_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO ticket (
        member_id,
        price,
        total_count,
        remaining_count,
        start_date
    )
    VALUES (
        p_member_id,
        p_price,
        p_total_count,
        p_total_count,
        p_start_date
    );

    SET v_ticket_id = LAST_INSERT_ID();

    INSERT INTO payment (ticket_id)
    VALUES (v_ticket_id);

    COMMIT;

    SELECT t.id, t.member_id, t.price, t.total_count,
           t.remaining_count, t.start_date, t.expire_date, p.paid_at
    FROM ticket t
    JOIN payment p ON p.ticket_id = t.id
    WHERE t.id = v_ticket_id;
END //

DELIMITER ;


-- F-06 수업 개설

DELIMITER //

DROP PROCEDURE IF EXISTS create_class //

CREATE PROCEDURE create_class(
    IN p_trainer_id INT,
    IN p_start_at DATETIME,
    IN p_end_at DATETIME,
    IN p_max_members INT
)
BEGIN
    DECLARE v_trainer_id INT DEFAULT NULL;
    DECLARE v_overlap_count INT DEFAULT 0;
    DECLARE v_class_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. 트레이너 존재 확인 및 잠금
    SELECT id
    INTO v_trainer_id
    FROM trainer
    WHERE id = p_trainer_id
    FOR UPDATE;

    IF v_trainer_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '존재하지 않는 트레이너입니다.';
    END IF;

    -- 2. 시간 및 정원 검사
    IF p_start_at IS NULL
       OR p_end_at IS NULL
       OR p_start_at >= p_end_at THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '수업 시간이 올바르지 않습니다.';
    END IF;

    IF p_max_members IS NULL OR p_max_members <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '최대 인원은 1명 이상이어야 합니다.';
    END IF;

    -- 3. 같은 트레이너의 수업 시간 중복 확인
    SELECT COUNT(*)
    INTO v_overlap_count
    FROM class_session
    WHERE trainer_id = p_trainer_id
      AND p_start_at < end_at
      AND p_end_at > start_at;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '해당 시간에 이미 수업이 있습니다.';
    END IF;

    -- 4. 수업 개설
    INSERT INTO class_session (
        trainer_id,
        start_at,
        end_at,
        max_members,
        status
    )
    VALUES (
        p_trainer_id,
        p_start_at,
        p_end_at,
        p_max_members,
        'OPEN'
    );

    SET v_class_id = LAST_INSERT_ID();
    COMMIT;

    SELECT id, trainer_id, start_at, end_at, max_members, status
    FROM class_session
    WHERE id = v_class_id;
END //

DELIMITER ;

-- F-07 수업 조회

DELIMITER //

DROP PROCEDURE IF EXISTS available_classes //

CREATE PROCEDURE available_classes(
    IN p_class_id INT
)
BEGIN
    SELECT
        c.id,
        c.trainer_id,
        t.name AS trainer_name,
        c.start_at,
        c.end_at,
        c.max_members,
        c.status,
        COUNT(r.id) AS used_count,
        c.max_members - COUNT(r.id) AS available_count
    FROM class_session c
    JOIN trainer t
        ON c.trainer_id = t.id
    LEFT JOIN reservation r
        ON c.id = r.class_session_id
        AND r.status IN ('RESERVED', 'DONE', 'NO_SHOW')
    WHERE c.id = p_class_id
    GROUP BY
        c.id,
        c.trainer_id,
        t.name,
        c.start_at,
        c.end_at,
        c.max_members,
        c.status;
END //

DELIMITER ;


-- F-08 수업 예약
DELIMITER //

DROP PROCEDURE IF EXISTS book_class //

CREATE PROCEDURE book_class(
    IN p_class_id INT,
    IN p_ticket_id INT
)
BEGIN
    DECLARE v_start_at DATETIME DEFAULT NULL;
    DECLARE v_end_at DATETIME;
    DECLARE v_status VARCHAR(10);
    DECLARE v_max_members INT;
    DECLARE v_used_count INT DEFAULT 0;

    DECLARE v_remaining_count INT DEFAULT NULL;
    DECLARE v_remaining_after INT;
    DECLARE v_start_date DATE;
    DECLARE v_expire_date DATE;
    DECLARE v_member_id INT;
    DECLARE v_locked_member_id INT;

    DECLARE v_payment_count INT DEFAULT 0;
    DECLARE v_duplicate_count INT DEFAULT 0;
    DECLARE v_reservation_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. 수업 정보 확인 및 잠금
    SELECT start_at, end_at, status, max_members
    INTO v_start_at, v_end_at, v_status, v_max_members
    FROM class_session
    WHERE id = p_class_id
    FOR UPDATE;

    IF v_start_at IS NULL
       OR v_status <> 'OPEN'
       OR v_start_at <= NOW() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '예약할 수 없는 수업입니다.';
    END IF;

    -- 2. 이용권 정보 확인 및 잠금
    SELECT remaining_count, start_date, expire_date, member_id
    INTO v_remaining_count, v_start_date, v_expire_date, v_member_id
    FROM ticket
    WHERE id = p_ticket_id
    FOR UPDATE;

    IF v_remaining_count IS NULL
       OR v_remaining_count <= 0
       OR DATE(v_start_at) NOT BETWEEN v_start_date AND v_expire_date THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '사용할 수 없는 이용권입니다.';
    END IF;

    -- 회원 단위로 직렬화해 서로 다른 이용권/수업의 동시 예약도 검사한다.
    SELECT id
    INTO v_locked_member_id
    FROM member
    WHERE id = v_member_id
    FOR UPDATE;

    -- 3. 결제 여부 확인
    SELECT COUNT(*)
    INTO v_payment_count
    FROM payment
    WHERE ticket_id = p_ticket_id;

    IF v_payment_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '결제되지 않은 이용권입니다.';
    END IF;

    -- 4. 정원 확인
    SELECT COUNT(*)
    INTO v_used_count
    FROM reservation
    WHERE class_session_id = p_class_id
      AND status IN ('RESERVED', 'DONE', 'NO_SHOW');

    IF v_used_count >= v_max_members THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '수업 정원이 가득 찼습니다.';
    END IF;

    -- 5. 중복 예약 방지
    SELECT COUNT(*)
    INTO v_duplicate_count
    FROM reservation
    WHERE class_session_id = p_class_id
      AND ticket_id = p_ticket_id
      AND status IN ('RESERVED', 'DONE', 'NO_SHOW');

    IF v_duplicate_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '이미 예약한 수업입니다.';
    END IF;

    SELECT COUNT(*)
    INTO v_duplicate_count
    FROM reservation r
    JOIN ticket t ON t.id = r.ticket_id
    JOIN class_session c ON c.id = r.class_session_id
    WHERE t.member_id = v_member_id
      AND r.status IN ('RESERVED', 'DONE', 'NO_SHOW')
      AND c.start_at < v_end_at
      AND c.end_at > v_start_at;

    IF v_duplicate_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '같은 시간에 이미 예약한 수업이 있습니다.';
    END IF;

    -- 6. 예약 생성
    INSERT INTO reservation (class_session_id, ticket_id)
    VALUES (p_class_id, p_ticket_id);

    SET v_reservation_id = LAST_INSERT_ID();

    -- 7. 예약 시 이용권 잔여 횟수 1회 차감
    UPDATE ticket
    SET remaining_count = remaining_count - 1
    WHERE id = p_ticket_id;

    SET v_remaining_after = v_remaining_count - 1;

    -- 8. 정원이 차면 CLOSE로 변경
    IF v_used_count + 1 >= v_max_members THEN
        UPDATE class_session
        SET status = 'CLOSE'
        WHERE id = p_class_id;
    END IF;

    COMMIT;

    -- 9. 예약 결과 반환
    SELECT v_reservation_id AS reservation_id,
           'RESERVED' AS reservation_status,
           v_remaining_after AS remaining_count;

END //

DELIMITER ;


-- F-09 예약 취소
DELIMITER //

DROP PROCEDURE IF EXISTS cancel_reservation //

CREATE PROCEDURE cancel_reservation(
    IN p_reservation_id INT
)
BEGIN
    DECLARE v_class_id INT DEFAULT NULL;
    DECLARE v_ticket_id INT DEFAULT NULL;
    DECLARE v_status VARCHAR(10);
    DECLARE v_start_at DATETIME;
    DECLARE v_max_members INT;
    DECLARE v_used_count INT;
    DECLARE v_class_status VARCHAR(10);
    DECLARE v_cancel_time DATETIME;
    DECLARE v_refunded TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. 예약에 연결된 수업 ID 확인
    SELECT class_session_id
    INTO v_class_id
    FROM reservation
    WHERE id = p_reservation_id;

    IF v_class_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '존재하지 않는 예약입니다.';
    END IF;

    -- 2. 수업 정보 확인 및 잠금
    SELECT start_at, max_members
    INTO v_start_at, v_max_members
    FROM class_session
    WHERE id = v_class_id
    FOR UPDATE;

    -- 3. 예약 정보 확인 및 잠금
    SELECT ticket_id, status
    INTO v_ticket_id, v_status
    FROM reservation
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF v_status IS NULL OR v_status <> 'RESERVED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '취소할 수 없는 예약입니다.';
    END IF;

    -- 4. 취소 시각 기록
    SET v_cancel_time = NOW();

    UPDATE reservation
    SET status = 'CANCELED',
        canceled_at = v_cancel_time
    WHERE id = p_reservation_id;

    -- 5. 수업 시작 48시간 전 또는 그 이전이면 1회 복구
    IF v_cancel_time <= DATE_SUB(v_start_at, INTERVAL 48 HOUR) THEN
        UPDATE ticket
        SET remaining_count = remaining_count + 1
        WHERE id = v_ticket_id;

        SET v_refunded = 1;
    END IF;

    -- 6. 취소 후 정원 다시 계산
    SELECT COUNT(*)
    INTO v_used_count
    FROM reservation
    WHERE class_session_id = v_class_id
      AND status IN ('RESERVED', 'DONE', 'NO_SHOW');

    -- 7. 빈자리가 생기면 OPEN으로 변경
    IF v_used_count < v_max_members THEN
        UPDATE class_session
        SET status = 'OPEN'
        WHERE id = v_class_id;
    END IF;

    -- 8. 변경된 수업 상태 확인
    SELECT status
    INTO v_class_status
    FROM class_session
    WHERE id = v_class_id;

    COMMIT;

    -- 9. 취소 결과 반환
    SELECT
        p_reservation_id AS reservation_id,
        v_cancel_time AS canceled_at,
        v_refunded AS count_refunded,
        v_class_status AS class_status;

END //

DELIMITER ;


-- F-10 수업 결과 기록
DELIMITER //

DROP PROCEDURE IF EXISTS mark_attendance //

CREATE PROCEDURE mark_attendance(
    IN p_reservation_id INT,
    IN p_result_status VARCHAR(10)
)
BEGIN
    DECLARE v_class_id INT DEFAULT NULL;
    DECLARE v_current_status VARCHAR(10);
    DECLARE v_end_at DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- 1. 결과 상태 확인
    IF p_result_status IS NULL
       OR p_result_status NOT IN ('DONE', 'NO_SHOW') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '결과는 DONE 또는 NO_SHOW여야 합니다.';
    END IF;

    START TRANSACTION;

    -- 2. 예약 존재 여부 확인
    SELECT class_session_id
    INTO v_class_id
    FROM reservation
    WHERE id = p_reservation_id;

    IF v_class_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '존재하지 않는 예약입니다.';
    END IF;

    -- 3. 수업 정보 확인 및 잠금
    SELECT end_at
    INTO v_end_at
    FROM class_session
    WHERE id = v_class_id
    FOR UPDATE;

    -- 4. 수업 종료 여부 확인
    IF NOW() < v_end_at THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '수업 종료 전에는 결과를 기록할 수 없습니다.';
    END IF;

    -- 5. 예약 상태 확인 및 잠금
    SELECT status
    INTO v_current_status
    FROM reservation
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF v_current_status IS NULL
       OR v_current_status <> 'RESERVED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '결과를 기록할 수 없는 예약입니다.';
    END IF;

    -- 6. 예약 상태만 변경
    UPDATE reservation
    SET status = p_result_status
    WHERE id = p_reservation_id;

    -- 이용권 횟수는 예약할 때 차감했으므로
    -- 수업 결과 기록 시 다시 차감하지 않음

    COMMIT;

    -- 7. 처리 결과 반환
    SELECT
        p_reservation_id AS reservation_id,
        p_result_status AS reservation_status;

END //

DELIMITER ;
