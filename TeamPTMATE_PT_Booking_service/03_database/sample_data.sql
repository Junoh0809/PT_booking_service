-- schema.sql과 objects.sql을 적용한 새 DB에서 한 번 실행합니다.
USE pt_booking;

-- 이용권 종류 2개는 구매 전에 등록됩니다. 10회권은 아무도 구매하지 않아도 조회됩니다.
INSERT INTO ticket_type (name, price, total_count)
VALUES ('PT 5회권', 250000, 5),
       ('PT 10회권', 450000, 10);
SET @ticket_type_1 = (SELECT id FROM ticket_type WHERE name = 'PT 5회권');

-- 회원 2명: 각각 이용권을 구매하고 같은 수업을 예약합니다.
CALL register_member('김민지', '010-1000-0001', '1998-04-12');
SET @member_1 = LAST_INSERT_ID();
CALL register_member('박서준', '010-1000-0002', '1995-09-20');
SET @member_2 = LAST_INSERT_ID();

-- 트레이너 2명: 같은 시간에 수업을 열어 회원 시간 중복 예약을 확인합니다.
CALL register_trainer('오지훈', '010-2000-0001', '1989-06-10', '2021-03-01');
SET @trainer_1 = LAST_INSERT_ID();
CALL register_trainer('최유나', '010-2000-0002', '1992-11-03', '2022-07-01');
SET @trainer_2 = LAST_INSERT_ID();

-- 두 회원이 등록된 PT 5회권 종류를 선택해 한 장씩 구매합니다.
CALL purchase_ticket(@member_1, @ticket_type_1, CURRENT_DATE());
SELECT id INTO @ticket_1 FROM ticket WHERE member_id = @member_1 ORDER BY id DESC LIMIT 1;
CALL purchase_ticket(@member_2, @ticket_type_1, CURRENT_DATE());
SELECT id INTO @ticket_2 FROM ticket WHERE member_id = @member_2 ORDER BY id DESC LIMIT 1;

-- 두 수업은 같은 시간, 다른 트레이너입니다. 첫 수업은 정원 2명입니다.
SET @class_day = DATE_ADD(CURRENT_DATE(), INTERVAL 7 DAY);
SET @class_start = TIMESTAMP(@class_day, '10:00:00');
SET @class_end = TIMESTAMP(@class_day, '11:00:00');

CALL create_class(@trainer_1, @class_start, @class_end, 2);
SET @class_1 = LAST_INSERT_ID();
CALL create_class(@trainer_2, @class_start, @class_end, 2);
SET @class_2 = LAST_INSERT_ID();

-- 두 회원이 첫 수업을 예약합니다. 정원이 차고 이용권은 각각 1회 차감됩니다.
CALL book_class(@class_1, @ticket_1);
CALL book_class(@class_1, @ticket_2);

-- 예상 결과: class_1은 CLOSE(정원 마감), class_2는 OPEN, 이용권 잔여 횟수는 각각 4회입니다.
SELECT id, trainer_id, start_at, max_members, status
FROM class_session ORDER BY id;
SELECT id, member_id, ticket_type_id, price, total_count, remaining_count
FROM ticket ORDER BY id;
-- 예약 ID와 상태를 확인한 뒤 아래 추가 쿼리의 입력값으로 사용합니다.
SELECT id, class_session_id, ticket_id, status
FROM reservation ORDER BY id;

-- 추가 검증(별도 실행): 같은 회원의 같은 시간 예약이므로 실패해야 합니다.
-- CALL book_class(@class_2, @ticket_1);
-- 예약 ID는 위 조회 결과에서 골라 입력합니다. 수업 48시간 전 취소는 이용권 횟수를 복구하고 정원을 다시 엽니다.
-- CALL cancel_reservation(<취소할 예약 ID>);
