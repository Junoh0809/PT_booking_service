USE pt_booking;

-- =========================================
-- 1. 회원별 PT 이용 현황 조회 뷰
-- =========================================

CREATE VIEW v_member_pt_summary AS
SELECT
    m.id AS member_id,
    m.name AS member_name,
    COALESCE(SUM(t.total_count), 0) AS total_pt_count,
    COALESCE(SUM(t.total_count - t.remaining_count), 0) AS used_pt_count,
    COALESCE(SUM(t.remaining_count), 0) AS remaining_pt_count
FROM member m
LEFT JOIN ticket t
    ON m.id = t.member_id
GROUP BY
    m.id,
    m.name;


-- =========================================
-- 2. 트레이너별 수업 운영 현황 조회 뷰
-- =========================================

CREATE VIEW v_trainer_class_summary AS
SELECT
    t.id AS trainer_id,
    t.name AS trainer_name,
    COUNT(DISTINCT c.id) AS total_classes,
    COUNT(CASE
        WHEN r.status IN ('RESERVED', 'DONE', 'NO_SHOW')
        THEN 1
    END) AS total_reservations,
    COUNT(CASE
        WHEN r.status = 'DONE'
        THEN 1
    END) AS completed_count,
    COUNT(CASE
        WHEN r.status = 'NO_SHOW'
        THEN 1
    END) AS no_show_count
FROM trainer t
LEFT JOIN class_session c
    ON t.id = c.trainer_id
LEFT JOIN reservation r
    ON c.id = r.class_session_id
GROUP BY
    t.id,
    t.name;