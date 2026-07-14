-- Per-lesson teacher rate: the rate paid to the teacher for THIS specific
-- lesson (600/700/750/900…), set manually per lesson. Takes priority over the
-- group override and the teacher's rate history in the salary accrual.
alter table app.lessons add column if not exists teacher_rate numeric(10,2);
