-- name: ascending
ASC

-- name: descending
DESC

-- name: by_name
name :order_direction

-- name: by_age
age :order_direction

-- name: get_people_by_age
SELECT name, age
  FROM person
 WHERE age >= :age
ORDER BY :order_by

-- name: legal_age
age >= 18

-- name: name_like
name LIKE :name

-- name: sql_and
AND

-- name: get_adults
SELECT name, age
  FROM person
 WHERE :where
