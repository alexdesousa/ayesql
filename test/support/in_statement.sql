-- name: get_people
SELECT *
  FROM people
 WHERE name IN ( :names )

-- name: get_names
SELECT name FROM people
