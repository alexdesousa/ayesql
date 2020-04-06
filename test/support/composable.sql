-- name: get_names
SELECT name FROM people

-- name: get_people
SELECT * FROM ( :get_names )

-- name: by_age
WHERE age >= :age

-- name: get_adults
SELECT age FROM people :by_age

