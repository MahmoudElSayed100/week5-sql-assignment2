-- customers with payment_id but no rental_id
SELECT 
	seRental.customer_id,
	sePayment.payment_id,
	seRental.rental_id
FROM public.payment as sePayment
LEFT OUTER JOIN public.rental as seRental
ON sePayment.customer_id = seRental.customer_id
WHERE 
	seRental.rental_id is null
GROUP BY
	seRental.customer_id,
	sePayment.payment_id,
	seRental.rental_id

-- avg number of films rented per customer grouped by city
SELECT
	total_rentals_subQ.city,
	total_rentals_subQ.customer_id,
	ROUND(AVG(total_rentals_per_customer),2) AS avg_rentals_per_customer
FROM(
	SELECT
		seCity.city,
		seCustomer.customer_id,
		COUNT(seRental.rental_id) AS total_rentals_per_customer
	FROM public.rental as seRental
	INNER JOIN public.customer AS seCustomer
	ON seRental.customer_id = seCustomer.customer_id
	INNER JOIN public.address as seAddress
	ON seCustomer.address_id = seAddress.address_id
	INNER JOIN public.city as seCity
	ON seAddress.city_id = seCity.city_id
	GROUP BY 
		seCity.city,
		seCustomer.customer_id
) AS total_rentals_subQ
GROUP BY 
	total_rentals_subQ.city,
	total_rentals_subQ.customer_id
ORDER BY
	total_rentals_subQ.city

--films that have been rented more than the avg number of times and not 
--in inventory
SELECT
	seInventory.inventory_id,
	seFilm.film_id,
	seFilm.title
FROM public.rental as seRental
LEFT OUTER JOIN public.inventory as seInventory
ON seRental.inventory_id = seInventory.inventory_id
LEFT OUTER JOIN public.film AS seFilm
ON seInventory.film_id = seFilm.film_id
GROUP BY 
	seInventory.inventory_id,
	seFilm.film_id,
	seFilm.title
HAVING
	COUNT(seRental.rental_id)
	>
	(SELECT 
		AVG(rental_count)
	FROM(
		SELECT
			seInv.film_id,
			COUNT(rental_id) as rental_count
		FROM public.rental as seRen
		LEFT OUTER JOIN public.inventory as seInv
		ON seRen.inventory_id = seInv.inventory_id
		GROUP BY film_id
	) as avg_rentals
)
AND seInventory.inventory_id = null

-- replacement cost of lost fimls for each store, considering rental his


SELECT
	seInv.store_id,
	SUM(seFilm.replacement_cost) as replacementCost
FROM public.rental as seRental
INNER JOIN public.inventory as seInv
ON seRental.inventory_id = seInv.inventory_id
INNER JOIN public.film as seFilm
ON seInv.film_id = seFilm.film_id
WHERE return_date is null
GROUP BY 
	seInv.store_id

-- top 5 most rented films in each category with their corresponding 
-- rental counts and revenue

WITH RANKED_FILMS_CTE AS(

	SELECT
		seCategory.category_id,
		seCategory.name,
		seFilm.film_id,
		seFilm.title,
		COUNT(seRental.rental_id) as Rental_Count,
		SUM(sePayment.amount) as Total_Revenue,
		ROW_NUMBER() OVER(PARTITION BY seCategory.category_id ORDER BY COUNT(seRental.rental_id) DESC ) AS ranking
	FROM public.payment AS sePayment
	LEFT OUTER JOIN public.rental AS seRental
	ON sePayment.rental_id = seRental.rental_id
	LEFT OUTER JOIN public.inventory as seInventory
	ON seRental.inventory_id = seInventory.inventory_id
	LEFT OUTER JOIN public.film AS  seFilm
	ON seInventory.film_id = seFilm.film_id
	INNER JOIN public.film_category AS seFilmCategory
	ON seFilm.film_id = seFilmCategory.film_id
	INNER JOIN public.category as seCategory
	ON seFilmCategory.category_id = seCategory.category_id
	GROUP BY
		seCategory.category_id,
		seCategory.name,
		seFilm.film_id,
		seFilm.title
)
SELECT
	rankedFilms.name AS category_name,
	rankedFilms.title as film_title,
	rankedFilms.rental_count,
	rankedFilms.total_revenue
FROM RANKED_FILMS_CTE AS rankedFilms
WHERE 
	rankedFilms.ranking <6
ORDER BY 
	rankedFilms.name,
	rankedFilms.title
	
-- query that updates the top 10 most frequently rented films
-- we assume we have a column named top_10_rented_films in public.film table
UPDATE public.film
SET top_10_rented_films = (
	SELECT
		sefilm.film_id,
		sefilm.title,
		COUNT(serental.rental_id ) AS rental_count
	FROM public.rental as serental
	INNER JOIN public.inventory as seinventory
	ON serental.inventory_id = seinventory.inventory_id
	INNER JOIN public.film as sefilm
	ON seinventory.film_id = sefilm.film_id
	GROUP BY 
		sefilm.film_id,
		sefilm.title
	ORDER BY
		rental_count DESC
	LIMIT 10
)

--stores where the revenue from film rentals exceeds the payments for all customers
WITH CUSTOMER_PAYMENT_REVENUE_CTE AS (
    SELECT
        secustomer.customer_id,
        SUM(sepayement.amount) AS total_payment_revenue
    FROM
        public.customer as secustomer
    LEFT OUTER JOIN
        payment as sepayement ON secustomer.customer_id = sepayement.customer_id
    GROUP BY
        secustomer.customer_id
)

SELECT
	seinventory.store_id,
	SUM(sepayment.amount) as TOTAL_REVENUE,
	SUM(customerpaymentrev.total_payment_revenue) AS TOTAL_CUSTOMER_PAYMENT
FROM public.payment as sepayment
LEFT OUTER JOIN CUSTOMER_PAYMENT_REVENUE_CTE AS customerpaymentrev
ON sepayment.customer_id = customerpaymentrev.customer_id
LEFT OUTER JOIN public.rental as serental
ON sepayment.rental_id = serental.rental_id
LEFT OUTER JOIN public.inventory as seinventory
ON serental.inventory_id = seinventory.inventory_id
GROUP BY 
	seinventory.store_id
HAVING
	SUM(sepayment.amount) 
	> 
	SUM(customerpaymentrev.total_payment_revenue)

-- avg rental duration and total revenue for each store 

SELECT
	seinv.store_id,
	AVG(sefilm.rental_duration) as avg_rental_duration,
	SUM(sepayment.amount) as total_revenue
FROM public.payment as sepayment
INNER JOIN public.rental AS serental
ON sepayment.rental_id = serental.rental_id
INNER JOIN public.inventory as seinv
ON serental.inventory_id = seinv.inventory_id
INNER JOIN public.film as sefilm
ON seinv.film_id = sefilm.film_id
GROUP BY
	seinv.store_id

-- seasonal variation in rental activity and payments for each store
WITH SeasonalDates AS (
    SELECT
        rental_date,
        CASE
            WHEN rental_date BETWEEN '2005-05-24' AND '2005-08-31' THEN 'Summer'
            WHEN rental_date BETWEEN '2005-12-01' AND '2006-02-28' THEN 'Winter'
        END AS season
    FROM public.rental
)
-- RENTAL VARIATION
SELECT
    sd.season,
    COUNT(serental.rental_id) AS rental_count
FROM SeasonalDates sd
LEFT OUTER JOIN public.rental AS serental 
ON sd.rental_date = serental.rental_date
GROUP BY sd.season
ORDER BY sd.season;
-- IN WINTER THE TOTAL RENTAL COUNTS ARE ~107% HIGHER THAN THE RENTAL COUNTS IN THE SUMMER

--PAYMENTS VARIATION
WITH SEASONAL_DATES_PAYMENT_CTE AS (
  SELECT
    payment_date,
    CASE
      WHEN EXTRACT(MONTH FROM payment_date) IN (12, 1, 2) THEN 'Winter'
      WHEN EXTRACT(MONTH FROM payment_date) IN (3, 4, 5) THEN 'Spring'
      WHEN EXTRACT(MONTH FROM payment_date) IN (6, 7, 8) THEN 'Summer'
      WHEN EXTRACT(MONTH FROM payment_date) IN (9, 10, 11) THEN 'Fall'
    END AS season
  FROM public.payment 
)
SELECT
    sd.season,
    SUM(sepayment.amount) AS total_payments
FROM SEASONAL_DATES_PAYMENT_CTE sd
LEFT OUTER JOIN public.payment as sepayment
ON sd.payment_date = sepayment.payment_date
GROUP BY sd.season
ORDER BY sd.season;
-- in spring, the payments are ~94% higher than the payments in winter





