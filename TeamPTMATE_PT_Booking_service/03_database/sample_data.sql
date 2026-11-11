-- Query.sql과 PT_Booking_Procedures.sql을 적용한 새 DB에서 한 번 실행합니다.
USE pt_booking;

-- 최소 시나리오: 예약 2건으로 정원 마감, 다른 트레이너의 같은 시간 수업으로 회원 중복 예약 방지 확인.
CALL register_member('김민지', '010-1000-0001', '1998-04-12');
SET @member_1 = LAST_INSERT_ID();
CALL register_member('박서준', '010-1000-0002', '1995-09-20');
SET @member_2 = LAST_INSERT_ID();

CALL register_trainer('오지훈', '010-2000-0001', '1989-06-10', '2021-03-01');
SET @trainer_1 = LAST_INSERT_ID();
CALL register_trainer('최유나', '010-2000-0002', '1992-11-03', '2022-07-01');
SET @trainer_2 = LAST_INSERT_ID();

CALL purchase_ticket(@member_1, 250000, 5, CURRENT_DATE());
SELECT id INTO @ticket_1 FROM ticket WHERE member_id = @member_1 ORDER BY id DESC LIMIT 1;
CALL purchase_ticket(@member_2, 250000, 5, CURRENT_DATE());
SELECT id INTO @ticket_2 FROM ticket WHERE member_id = @member_2 ORDER BY id DESC LIMIT 1;

SET @class_day = DATE_ADD(CURRENT_DATE(), INTERVAL 7 DAY);
SET @class_start = TIMESTAMP(@class_day, '10:00:00');
SET @class_end = TIMESTAMP(@class_day, '11:00:00');

CALL create_class(@trainer_1, @class_start, @class_end, 2);
SET @class_1 = LAST_INSERT_ID();
CALL create_class(@trainer_2, @class_start, @class_end, 2);
SET @class_2 = LAST_INSERT_ID();

CALL book_class(@class_1, @ticket_1);
CALL book_class(@class_1, @ticket_2);

-- 확인: class_1은 CLOSE, class_2는 OPEN. ticket별 잔여 횟수는 4회.
SELECT id, trainer_id, start_at, max_members, status
FROM class_session ORDER BY id;
SELECT id, member_id, total_count, remaining_count
FROM ticket ORDER BY id;
SELECT id, class_session_id, ticket_id, status
FROM reservation ORDER BY id;

-- 추가 검증은 별도로 실행: CALL book_class(@class_2, @ticket_1); -- 같은 회원의 시간 중복으로 실패
-- CALL cancel_reservation(1); -- 취소·48시간 전 횟수 복구·정원 재개방 확인 (예약 ID는 조회 결과로 지정)
