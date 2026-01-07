-- name: get_all_users
SELECT * FROM users;

-- name: get_user_by_id
SELECT * FROM users WHERE id = :user_id;
