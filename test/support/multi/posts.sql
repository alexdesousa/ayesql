-- name: get_all_posts
SELECT * FROM posts;

-- name: get_posts_by_user
SELECT * FROM posts WHERE user_id = :user_id;
