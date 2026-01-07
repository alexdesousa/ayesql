-- name: get_posts_from_active_users
SELECT * FROM posts WHERE user_id IN (:get_active_users);
