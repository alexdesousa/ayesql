-- name: get_comments_by_post
SELECT * FROM comments WHERE post_id = :post_id;
