-- name: by_location
AND location = :location

-- name: get_servers
SELECT *
  FROM server
 WHERE hostname = :hostname
       :_by_location
