-- Create, use bike_stores database
DROP DATABASE IF EXISTS bike_store;
CREATE DATABASE bike_store;
USE bike_store;

-- Create table customers
DROP TABLE IF EXISTS customers;
CREATE TABLE customers(
    customer_id INT NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    phone VARCHAR(50),
    email VARCHAR(50),
    street VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(50),
    zip_code INT,
    PRIMARY KEY (customer_id)
);

-- Create table stores
DROP TABLE IF EXISTS stores;
CREATE TABLE stores(
    store_id SMALLINT NOT NULL,
    store_name VARCHAR(50),
    phone VARCHAR(50),
    email VARCHAR(50),
    street VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(50),
    zip_code INT,
    PRIMARY KEY (store_id)
);

-- Create table staffs
DROP TABLE IF EXISTS staffs;
CREATE TABLE staffs(
    staff_id SMALLINT NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    phone VARCHAR(50),
    email VARCHAR(50),
    active SMALLINT,
    store_id SMALLINT,
    manager_id SMALLINT,
    PRIMARY KEY (staff_id),
    FOREIGN KEY (store_id) REFERENCES stores(store_id),
    FOREIGN KEY (manager_id) REFERENCES staffs(staff_id)
);

-- Create table orders
DROP TABLE IF EXISTS orders;
CREATE TABLE orders(
    order_id INT NOT NULL,
    customer_id INT NOT NULL,
    order_status SMALLINT NOT NULL,
    order_date VARCHAR(20),
    required_date VARCHAR(20),
    shipped_date VARCHAR(20),
    staff_id  SMALLINT NOT NULL,
    store_id SMALLINT NOT NULL,
    PRIMARY KEY (order_id), 
    FOREIGN KEY (store_id) REFERENCES stores(store_id),
    FOREIGN KEY (staff_id) REFERENCES staffs(staff_id)
);

-- Create table categories
DROP TABLE IF EXISTS categories;
CREATE TABLE categories(
    category_id SMALLINT NOT NULL,
    category_name VARCHAR(50),
    PRIMARY KEY (category_id)
);

-- Create table brands
DROP TABLE IF EXISTS brands;
CREATE TABLE brands(
    brand_id SMALLINT NOT NULL,
    brand_name VARCHAR(50),
    PRIMARY KEY (brand_id)
);

-- Create table products
DROP TABLE IF EXISTS products;
CREATE TABLE products(
  product_id SMALLINT NOT NULL,
  product_name VARCHAR(100),
  model_year SMALLINT,
  list_price FLOAT,
  category_id SMALLINT, 
  brand_id SMALLINT,
  FOREIGN KEY (category_id) REFERENCES categories(category_id),
  FOREIGN KEY (brand_id) REFERENCES brands(brand_id),
  PRIMARY KEY (product_id)
);

-- Create table order_items
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items(
    order_id INT NOT NULL,
    product_id SMALLINT,
    quantity SMALLINT,
    list_price FLOAT,
    discount FLOAT,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Create table stocks
DROP TABLE IF EXISTS stocks;
CREATE TABLE stocks(
    store_id SMALLINT NOT NULL,
    product_id SMALLINT NOT NULL,
    quantity SMALLINT,
    FOREIGN KEY (store_id) REFERENCES stores(store_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- After that, import wizard data into tables
-- Update formats of date columns in table orders
UPDATE orders
SET 
    order_date = STR_TO_DATE(order_date, '%Y-%m-%d'),
    required_date = STR_TO_DATE(required_date, '%Y-%m-%d'),
    shipped_date = STR_TO_DATE(shipped_date, '%Y-%m-%d');

-- Store procedures with examples
-- 1. Calculate daily revenue
DROP PROCEDURE IF EXISTS calculate_daily_revenue
DELIMITER //
CREATE PROCEDURE calculate_daily_revenue(
    IN p_shipped_date DATE
)
BEGIN
    DECLARE total_revenue DECIMAL(10, 2);
    
    SELECT SUM(oi.quantity * oi.list_price * (1 - oi.discount)) INTO total_revenue
    FROM orders o
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.shipped_date = p_shipped_date;
    
    SELECT total_revenue;
END //
DELIMITER ;
CALL calculate_daily_revenue('2016-01-03')

-- 2. Report total revenue from sales of products in a range of time
DROP PROCEDURE IF EXISTS generate_product_sales_report
DELIMITER //
CREATE PROCEDURE generate_product_sales_report(
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    DECLARE v_total_sales FLOAT;

    -- Create a temporary table to store product sales data
    CREATE TEMPORARY TABLE temp_product_sales (
        product_id INT,
        product_name VARCHAR(100),
        total_quantity_sold INT,
        total_sales_amount FLOAT
    );

    -- Calculate total sales for each product within the date range
    INSERT INTO temp_product_sales (product_id, product_name, total_quantity_sold, total_sales_amount)
    SELECT oi.product_id,
           p.product_name,
           SUM(oi.quantity) AS total_quantity_sold,
           SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_sales_amount
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.order_date BETWEEN p_start_date AND p_end_date
    GROUP BY oi.product_id;

    -- Retrieve total overall sales within the date range
    SELECT SUM(total_sales_amount) INTO v_total_sales
    FROM temp_product_sales;

    -- Display product sales report
    SELECT *,
           ROUND((total_sales_amount / v_total_sales) * 100, 2) AS sales_percentage_of_total
    FROM temp_product_sales
    ORDER BY total_quantity_sold DESC;

    -- Drop the temporary table
    DROP TEMPORARY TABLE IF EXISTS temp_product_sales;
END //
DELIMITER ;

CALL generate_product_sales_report('2016-01-01', '2016-06-01')

-- 3. Find store revenue in each month and its changes compared to the previous month based on store id
DROP PROCEDURE IF EXISTS get_store_time_sale
DELIMITER //
CREATE PROCEDURE get_store_time_sale(IN ID INT)
BEGIN
	WITH total_bill AS (SELECT order_id, SUM(total) AS total
						FROM (SELECT order_id, product_id, 
ROUND(quantity * ((1 - discount) * list_price), 2) AS total
							FROM order_items) o
						GROUP BY order_id),

		 order_detail AS (SELECT o.order_id, o.store_id, o.shipped_date, t.total
						  FROM orders o
						  INNER JOIN total_bill t
						  ON o.order_id = t.order_id
						  WHERE order_status = 4 AND o.store_id = ID),
                          
		 time_sale AS (SELECT store_id, MONTH(shipped_date) AS month, YEAR(shipped_date) AS year,
					   SUM(total) AS total_revenue
					   FROM order_detail
					   GROUP BY store_id, month, year),
                       
		 revenue_comparison AS (SELECT DATE_FORMAT(CONCAT(year, '-', month, '-01'), '%Y-%m') time, total_revenue, 
								LAG(total_revenue, 1, 0) OVER (ORDER BY DATE_FORMAT(CONCAT(year, '-', month, '-01'), '%Y-%m')) AS prev_revenue
								FROM time_sale)

	SELECT time, ROUND(total_revenue, 2) AS total_revenue, ROUND(prev_revenue, 2) AS prev_revenue, 
    ROUND(((total_revenue - prev_revenue) / prev_revenue) * 100, 2) AS percent_change
    FROM revenue_comparison;
END //
DELIMITER ;

CALL get_store_time_sale(3)

-- 4. Show top 5 best sellers based on month and year
DROP PROCEDURE IF EXISTS list_best_selling_product
DELIMITER //
CREATE PROCEDURE list_best_selling_product(
    IN p_store_id SMALLINT,
    IN p_month INT,
    IN p_year INT
)
BEGIN
    SELECT 
		p.*, 
        SUM(oi.quantity) AS total_quantity
    FROM orders o
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    INNER JOIN products p ON oi.product_id = p.product_id
    WHERE o.store_id = p_store_id
    AND MONTH(o.order_date) = p_month
    AND YEAR(o.order_date) = p_year
    GROUP BY p.product_id, p.product_name, p.model_year, p.list_price, 		p.category_id, p.brand_id
    ORDER BY total_quantity DESC
    LIMIT 5;
END //
DELIMITER ;

CALL list_best_selling_product(1, 6, 2016);

-- 5. Find store stocks quantity based on store id
DROP PROCEDURE IF EXISTS get_store_stocks
DELIMITER //
CREATE PROCEDURE get_store_stocks(IN ID SMALLINT)
BEGIN
   SELECT * FROM stores WHERE store_id = ID;
WITH product_by_category AS (SELECT p.product_id, p.product_name, c.category_name
								FROM products p
								INNER JOIN categories c
								ON p.category_id = c.category_id)
	SELECT s.store_id, p.category_name, SUM(s.quantity) AS total_stocks
	FROM stocks s
	JOIN product_by_category p
	ON s.product_id = p.product_id
	GROUP BY s.store_id, p.category_name
   HAVING s.store_id = ID;
END //
DELIMITER ;

CALL get_store_stocks(1);

-- 6. Find orders based on store id and order status
DROP PROCEDURE IF EXISTS find_order
DELIMITER //
CREATE PROCEDURE find_order(
	IN p_store_id SMALLINT,
   IN p_order_status SMALLINT
)
BEGIN
    SELECT store_id, order_status, COUNT(*) AS order_count
    FROM orders
    WHERE  store_id = p_store_id AND order_status = p_order_status
    GROUP BY store_id, order_status;
END //
DELIMITER ;

-- 7. Find all orders of a customer based on their id
DROP PROCEDURE IF EXISTS get_customer_orders
DELIMITER //
CREATE PROCEDURE get_customer_orders(
    IN p_customer_id SMALLINT
)
BEGIN
    SELECT o.order_id, o.order_status, o.order_date, o.required_date, o.shipped_date, o.store_id, o.staff_id
    FROM orders o
    WHERE o.customer_id = p_customer_id;
END//
DELIMITER ;

CALL get_customer_orders(123);

-- 8. Calculate top customer of the month
DROP PROCEDURE IF EXISTS calculate_top_customer_of_month
DELIMITER //
CREATE PROCEDURE calculate_top_customer_of_month(
    IN p_order_date DATE,
    IN p_limit INT
)
BEGIN
    DECLARE start_date DATE;
    DECLARE end_date DATE;

    -- Calculate from the first and last day of the month from the input date
    SET start_date = DATE_FORMAT(p_order_date, '%Y-%m-01');
    SET end_date = LAST_DAY(p_order_date);

    -- Create a temporary table to store a list of the customers with highest spending
    CREATE TEMPORARY TABLE temp_top_customers (
        customer_id INT,
        total_spent DECIMAL(10, 2)
    );

    -- Take the list of the customers with highest spending in that month
    INSERT INTO temp_top_customers (customer_id, total_spent)
    SELECT o.customer_id, SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_spent
    FROM orders o
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_date BETWEEN start_date AND end_date
    GROUP BY o.customer_id
    ORDER BY total_spent DESC
    LIMIT p_limit;

    -- Take customers information detail from the temporary table
    SELECT c.first_name, c.last_name, ttc.total_spent
    FROM customers c
    INNER JOIN temp_top_customers ttc ON c.customer_id = ttc.customer_id;

    -- Delete the temporary table 
    DROP TEMPORARY TABLE IF EXISTS temp_top_customers;
END//
DELIMITER ;

CALL calculate_top_customer_of_month('2016-01-29', 5);

-- Triggers with example 
-- 1. Adjust total amount spent in an order when inserting new order items
ALTER TABLE orders
ADD COLUMN total_amount DECIMAL(10, 2) DEFAULT 0 AFTER shipped_date;

UPDATE orders o
JOIN (SELECT order_id, SUM(quantity * list_price * (1 - discount)) AS total_spend
      FROM order_items
      GROUP BY order_id) oi
ON o.order_id = oi.order_id
SET o.total_amount = oi.total_spend;
SELECT * FROM orders

DROP TRIGGER IF EXISTS update_total_order_amount
DELIMITER //
CREATE TRIGGER update_total_order_amount
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE v_order_total FLOAT;

    SELECT SUM(quantity * list_price * (1 - discount))
    INTO v_order_total
    FROM order_items
    WHERE order_id = NEW.order_id;

    UPDATE orders
    SET total_amount = v_order_total
    WHERE order_id = NEW.order_id;
END //
DELIMITER ;
-- Test example
INSERT INTO order_items VALUES (1, 10, 3, 1549, 0.05); 
SELECT * FROM orders WHERE order_id = 1;

-- 2. Update customer loyalty point when create new order
ALTER TABLE customers
ADD COLUMN loyalty_point DECIMAL(10,2) DEFAULT 0;

UPDATE customers 
JOIN (
SELECT customer_id, ROUND(SUM(total_pay), 2) AS total_pay,  ROUND(ROUND(SUM(total_pay) / 10, 2)) AS loyalty
    FROM orders o
    JOIN (
        SELECT order_id, SUM(quantity * list_price * (1 - discount)) AS total_pay
        FROM order_items
        GROUP BY order_id
    ) oi ON o.order_id = oi.order_id
    GROUP BY customer_id
) customer_loyalty ON customers.customer_id = customer_loyalty.customer_id
SET customers.loyalty_point = customer_loyalty.loyalty;
SELECT * FROM customers

DROP TRIGGER IF EXISTS update_customer_loyalty_points
DELIMITER //
CREATE TRIGGER update_customer_loyalty_points
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE new_cus_loyalty INT ;
    
    SELECT ROUND(ROUND(SUM(total_pay) / 10, 2))
    INTO new_cus_loyalty
    FROM orders o
    JOIN (
        SELECT order_id, SUM(quantity * list_price * (1 - discount)) AS total_pay
        FROM order_items
        GROUP BY order_id
    ) oi ON o.order_id = oi.order_id
    GROUP BY customer_id
    HAVING customer_id = (SELECT customer_id FROM orders WHERE order_id = NEW.order_id);

    UPDATE customers
    SET loyalty_point = new_cus_loyalty
    WHERE customer_id = (SELECT customer_id FROM orders WHERE order_id = NEW.order_id);
END //
DELIMITER ;

-- Test example:
INSERT INTO orders VALUES (1701, 259, 4, '2019-01-01', '2019-01-02', '2019-01-02', 0, 2, 1);
INSERT INTO order_items VALUES(1701, 1, 2, 379.99, 0.1);
INSERT INTO order_items VALUES(1701, 2, 1, 749.99, 0.1);

SELECT * FROM customers WHERE customer_id = 259;

-- 3. Check the orders and customers table when deleting a customer
DROP TRIGGER IF EXISTS delete_customer_orders

DELIMITER //
CREATE TRIGGER delete_customer_orders
BEFORE DELETE ON customers
FOR EACH ROW
BEGIN
    DELETE FROM orders WHERE customer_id = OLD.customer_id;
END//
DELIMITER ;

DROP TRIGGER IF EXISTS order_items
DELIMITER //
CREATE TRIGGER order_items
BEFORE DELETE ON orders
FOR EACH ROW
BEGIN
    DELETE FROM order_items WHERE order_id = OLD.order_id;
END//
DELIMITER ;
-- Test example:
DELETE FROM customers WHERE customer_id = 5;
SELECT * FROM order_items WHERE order_id = 571;
SELECT * FROM orders WHERE customer_id = 5;

-- 4. Update shipped date and order status for new order
DROP TRIGGER IF EXISTS order_items
DELIMITER //
CREATE TRIGGER update_order_status_and_shipped_date
BEFORE INSERT ON orders 
FOR EACH ROW
BEGIN
    IF NEW.order_status IN (1, 2, 3) THEN
        SET NEW.shipped_date = NULL;
    ELSEIF NEW.order_status = 4 THEN
        SET NEW.shipped_date = NEW.required_date;
    END IF;
END//
DELIMITER ;
-- Test example:
INSERT INTO orders (order_id, customer_id, order_status, order_date, required_date, total_amount, staff_id, store_id)
VALUES
	(1650, 100, 4, '2016-01-01', '2016-01-03', 0, 1, 1);
SELECT * FROM orders WHERE order_id = 1650;

-- 5. Update order status to 4 (shipped) when updating new shipped date of existed order
DROP TRIGGER IF EXISTS update_order_status
DELIMITER //
CREATE TRIGGER update_order_status
BEFORE UPDATE ON orders
FOR EACH ROW
BEGIN
    IF NEW.shipped_date IS NOT NULL AND OLD.shipped_date IS NULL AND OLD.order_status != 3 THEN
        SET NEW.order_status = 4;
    END IF;
END //
DELIMITER ;
-- Test example:
UPDATE orders SET shipped_date = '2018-05-01' WHERE order_id = 1602;
SELECT * FROM orders WHERE order_id = 1602;

-- 6. Update stock quantity when creating new order
DROP TRIGGER IF EXISTS after_sell_order
DELIMITER //
CREATE TRIGGER after_sell_order
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE product_stock INT;
    
    -- Take the stock quantity of the product
    SELECT quantity INTO product_stock
    FROM stocks
    WHERE product_id = NEW.product_id AND store_id = (SELECT store_id FROM orders WHERE order_id = NEW.order_id);
    
    -- Update the new stock quantity of the product
    IF product_stock >= NEW.quantity THEN
		UPDATE stocks
		SET quantity = product_stock - NEW.quantity
		WHERE product_id = NEW.product_id AND store_id = (SELECT store_id FROM orders WHERE order_id = NEW.order_id);
	
    ELSE
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock quantity';
	END IF;
END//
DELIMITER ;
-- Test example 1:
INSERT INTO order_items (order_id, product_id, quantity, list_price, discount)
VALUES (1, 1, 3, 10.99, 0.1);
SELECT * FROM stocks WHERE product_id = 1

-- 7. Update stock quantity when deleting new order
DROP TRIGGER IF EXISTS order_items
DELIMITER //
CREATE TRIGGER delete_order_item_after_delete
AFTER DELETE ON order_items
FOR EACH ROW
BEGIN
    -- Restore inventory quantities to their original values for specific products and stores
    UPDATE stocks
    SET quantity = quantity + OLD.quantity
    WHERE product_id = OLD.product_id 
    AND store_id = (SELECT store_id FROM orders WHERE order_id = OLD.order_id);
END//
DELIMITER ;
-- Test examples:
-- The stocks quantity before and after deleting the order items
INSERT INTO order_items (order_id, product_id, quantity, list_price, discount)
VALUES (1, 1, 5, 10.99, 0.1);

DELETE FROM order_items 
WHERE order_id = 1 AND product_id = 1 AND quantity = 5 AND list_price = 10.99 AND discount = 0.1;