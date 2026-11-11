-- schema.sql, objects.sql, sample_data.sql 실행 후 사용합니다.
-- sample_data.sql의 기본 데이터는 테스트 중 변경됩니다. 반복 검증은 새 DB에서 다시 시작하세요.
-- 각 '실패 예상' 구간은 에러가 정상 결과이므로 다른 쿼리와 따로 실행합니다.
USE pt_booking;

-- 정상 조회: 회원/트레이너 조회와 수업별 사용 인원·잔여 정원 집계
-- 이 구간만 실행할 때도 아래 ID 설정부터 CALL까지 같은 SQL 연결에서 함께 실행합니다.
-- sample_data.sql을 여러 번 넣었다면 각 회원·트레이너의 가장 최근 데이터를 사용합니다.
SET @member_1 = (SELECT id FROM member WHERE phone = '010-1000-0001' ORDER BY id DESC LIMIT 1);
SET @member_2 = (SELECT id FROM member WHERE phone = '010-1000-0002' ORDER BY id DESC LIMIT 1);
SET @trainer_1 = (SELECT id FROM trainer WHERE phone = '010-2000-0001' ORDER BY id DESC LIMIT 1);
SET @trainer_2 = (SELECT id FROM trainer WHERE phone = '010-2000-0002' ORDER BY id DESC LIMIT 1);
SET @ticket_1 = (SELECT id FROM ticket WHERE member_id = @member_1 ORDER BY id DESC LIMIT 1);
SET @ticket_2 = (SELECT id FROM ticket WHERE member_id = @member_2 ORDER BY id DESC LIMIT 1);
SET @class_1 = (SELECT id FROM class_session WHERE trainer_id = @trainer_1 AND start_at > NOW() ORDER BY start_at DESC, id DESC LIMIT 1);
SET @class_2 = (SELECT id FROM class_session WHERE trainer_id = @trainer_2 AND start_at > NOW() ORDER BY start_at DESC, id DESC LIMIT 1);
SELECT @member_1 AS member_id, @trainer_1 AS trainer_id,
       @class_1 AS first_class_id, @class_2 AS second_class_id;
CALL search_member(@member_1);
CALL search_trainer(@trainer_1);
CALL available_classes(@class_1);
CALL available_classes(@class_2);

-- 실패 예상: 같은 회원의 같은 시간대 예약은 다른 트레이너 수업이어도 거부되어야 합니다.
CALL book_class(@class_2, @ticket_1);

-- 실패 예상: 이미 정원이 찬 수업은 예약을 거부해야 합니다.
CALL book_class(@class_1, @ticket_1);

-- 정상 취소: 취소 시각은 수업 7일 전이므로 횟수 1회 복구, 수업은 OPEN으로 변경되어야 합니다.
SELECT id INTO @reservation_1 FROM reservation
 WHERE class_session_id = @class_1 AND ticket_id = @ticket_1 AND status = 'RESERVED';
CALL cancel_reservation(@reservation_1);
SELECT status FROM class_session WHERE id = @class_1;
SELECT remaining_count FROM ticket WHERE id = @ticket_1;

-- 정상 예약: 취소로 중복 예약이 해제된 뒤 class_2 예약에 성공하고 횟수 1회 차감되어야 합니다.
CALL book_class(@class_2, @ticket_1);
CALL available_classes(@class_2);
SELECT remaining_count FROM ticket WHERE id = @ticket_1;

-- 출석 결과 기록: 종료된 테스트 수업과 예약을 만들어 DONE 기록을 확인합니다.
-- 이후 member_1의 이용권 횟수는 1회 차감되며, DONE 예약은 정원에 계속 포함됩니다.
SET @past_start = TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 2 DAY), '10:00:00');
INSERT INTO class_session (trainer_id, start_at, end_at, max_members, status)
VALUES (@trainer_1, @past_start, DATE_ADD(@past_start, INTERVAL 1 HOUR), 1, 'OPEN');
SET @past_class = LAST_INSERT_ID();
INSERT INTO reservation (class_session_id, ticket_id)
VALUES (@past_class, @ticket_1);
SET @past_reservation = LAST_INSERT_ID();
UPDATE ticket SET remaining_count = remaining_count - 1 WHERE id = @ticket_1;
UPDATE class_session SET status = 'CLOSE' WHERE id = @past_class;
CALL mark_attendance(@past_reservation, 'DONE');
SELECT status FROM reservation WHERE id = @past_reservation;
SELECT status, max_members FROM class_session WHERE id = @past_class;

-- 제약조건 실패 예상: 허용하지 않는 출석 결과는 거부되어야 합니다.
CALL mark_attendance(@past_reservation, 'CANCELED');
