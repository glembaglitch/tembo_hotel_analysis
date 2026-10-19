--create schema and set search path to it
create schema tembo_hotel;

set search_path to tembo_hotel;

--create table
---import everything as text so that messy dates and numbers don’t stop the CSV from importing
create table bookings_staging (
     booking_id text,
     guest_name text,
     guest_phone text,
     guest_city text,
     guest_nationality text,
     room_no text,
     room_type text,
     room_rate_per_night text,
     check_in_date text,
     check_out_date text,
     nights_stayed text,
     staff_name text,
     staff_department text,
     staff_salary text,
     payment_method text,
     booking_status text,
     total_amount text,
     service_used text,
     service_price text,
     guest_rating text
);

--check what was imported
---confirm row count
select count(*) as imported_rows
from bookings_staging;

---find duplicate booking_ids
select booking_id, count(*) as copies
from bookings_staging 
group by booking_id 
having count(*) > 1;

---check blanks in important columns
select 
   count(*) filter (where nullif(btrim(booking_id), '') is null) as blank_booking_ids,
   count(*) filter(where nullif(btrim(guest_name), '') is null) as blank_guest_names,
   count(*) filter(where nullif(btrim(check_in_date), '') is null) as blank_check_in_dates,
   count(*) filter(where nullif(btrim(check_out_date), '') is null) as blank_check_out_dates,
   count(*) filter(where nullif(btrim(booking_status), '') is null) as blank_booking_statuses
from bookings_staging;

---review categories that need standardizing
select distinct booking_status
from bookings_staging 
order by booking_status;

select distinct payment_method 
from bookings_staging 
order by payment_method;

select distinct room_type 
from bookings_staging 
order by room_type;

---review date strings that are not iso format
select booking_id, check_in_date, check_out_date 
from bookings_staging 
where check_in_date !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or check_out_date !~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$';

--Make a working copy for cleaning
create table bookings_staging_clean
(like bookings_staging);

insert into bookings_staging_clean
select *
from bookings_staging;

---clean names and text spacing
select 
  booking_id,
  guest_name as old_name,
  initcap(btrim(guest_name)) as proposed_name,
  staff_name as old_staff_name,
  initcap(btrim(staff_name)) as proposed_staff_name
from bookings_staging_clean
where guest_name is distinct from initcap(btrim(guest_name))
   or staff_name is distinct from initcap(btrim(staff_name));

update bookings_staging_clean 
set 
    guest_name = nullif(initcap(btrim(guest_name)), ''),
    guest_city = nullif(initcap(btrim(guest_city)), ''),
    guest_nationality = nullif(initcap(btrim(guest_nationality)), ''),
    staff_name = nullif(initcap(btrim(staff_name)), ''),
    staff_department = nullif(initcap(btrim(staff_department)), ''),
    room_type = nullif(initcap(btrim(room_type)), ''),
    payment_method = nullif(initcap(btrim(payment_method)), ''),
    booking_status = nullif(initcap(btrim(booking_status)), ''),
    service_used = nullif(initcap(btrim(service_used)), '');

---clean phone numbers
----preview
with phone_preview as (
select 
    booking_id,
    guest_phone as old_phone,
    regexp_replace(coalesce(guest_phone, ''), '[^0-9]', '', 'g') as digits
from bookings_staging_clean
)
select 
  booking_id,
  old_phone,
  case
  	when digits ~ '^2547[0-9]{8}$' then '0' || substring(digits from 4)
  	when digits ~ '^7[0-9]{8}$' then '0' || digits 
  	else digits
  end as proposed_phone 
from phone_preview 
where old_phone is distinct from 
   case
   	when digits ~ '^2547[0-9]{8}$' then '0' || substring(digits from 4)
   	when digits ~ '^7[0-9]{8}$' then '0' || digits  
   	else digits  
   end;

----update
update bookings_staging_clean
set guest_phone = 
   case
   	when regexp_replace(coalesce(guest_phone, ''), '[^0-9]', '', 'g')
   	     ~ '^2547[0-9]{8}$'
   	     then '0' || substring(
   	          regexp_replace(guest_phone, '[^0-9]', '', 'g')
   	          from 4
   	      )
   	when regexp_replace(coalesce(guest_phone, ''), '[^0-9]', '', 'g')
   	      ~ '^7[0-9]{8}$'
   	      then '0'|| regexp_replace(guest_phone, '[^0-9]', '', 'g')
   	else regexp_replace(coalesce(guest_phone, ''), '[^0-9]', '', 'g')
   end
where guest_phone is not null;

----confirm
select booking_id, guest_phone
from bookings_staging_clean
where guest_phone !~ '^07[0-9]{8}';

select 
    case 
        when nullif(btrim(guest_phone), '') is null then 'blank'
        when btrim(guest_phone) ~ '^07[0-9]{8}$' then 'valid'
        else 'nonblank invalid'
    end as phone_status,
    count(*) as rows
from bookings_staging_clean
group by phone_status;
   
----check non-blank invalid values and their lenght
select
    booking_id,
    guest_phone,
    length(btrim(guest_phone)) as phone_length
from bookings_staging_clean
where nullif(btrim(guest_phone), '') is not null
  and btrim(guest_phone) !~ '^07[0-9]{8}$';
  
select booking_id, guest_phone
from bookings_staging_clean
where guest_phone is not null
  and btrim(guest_phone) = '';

update bookings_staging_clean
set guest_phone = null
where guest_phone is not null
  and btrim(guest_phone) = '';

--clean numeric text
---inspect
select
    booking_id,
    staff_salary as old_salary,
    regexp_replace(coalesce(staff_salary, ''), '[^0-9.]', '', 'g') as proposed_salary,
    total_amount as old_amount,
    regexp_replace(coalesce(total_amount, ''), '[^0-9.]', '', 'g') as proposed_amount
from bookings_staging_clean
where staff_salary ~ '[^0-9.]'
   or total_amount ~ '[^0-9.]'
   or room_rate_per_night ~ '[^0-9.]'
   or service_price ~ '[^0-9.]';

---clean
update bookings_staging_clean
set
    room_no = nullif(regexp_replace(coalesce(room_no, ''), '[^0-9]', '', 'g'), ''),
    room_rate_per_night = nullif(regexp_replace(coalesce(room_rate_per_night, ''), '[^0-9.]', '', 'g'), ''),
    nights_stayed = nullif(regexp_replace(coalesce(nights_stayed, ''), '[^0-9]', '', 'g'), ''),
    staff_salary = nullif(regexp_replace(coalesce(staff_salary, ''), '[^0-9.]', '', 'g'), ''),
    total_amount = nullif(regexp_replace(coalesce(total_amount, ''), '[^0-9.]', '', 'g'), ''),
    service_price = nullif(regexp_replace(coalesce(service_price, ''), '[^0-9.]', '', 'g'), ''),
    guest_rating = nullif(regexp_replace(coalesce(guest_rating, ''), '[^0-9]', '', 'g'), '');

--date and categories
---review date formats
select
    'check_in_date' as column_name,
    case
        when check_in_date::text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then 'YYYY-MM-DD'
        when check_in_date::text ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' then 'slash: confirm D/M/Y or M/D/Y'
        when check_in_date::text ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' then 'hyphen: confirm D-M-Y or M-D-Y'
        when nullif(btrim(check_in_date::text), '') is null then 'blank'
        else 'other format'
    end as apparent_format,
    count(*) as rows
from bookings_staging_clean
group by 1, 2

union all

select
    'check_out_date',
    case
        when check_out_date::text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then 'YYYY-MM-DD'
        when check_out_date::text ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' then 'slash: confirm D/M/Y or M/D/Y'
        when check_out_date::text ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' then 'hyphen: confirm D-M-Y or M-D-Y'
        when nullif(btrim(check_out_date::text), '') is null then 'blank'
        else 'other format'
    end,
    count(*)
from bookings_staging_clean
group by 1, 2
order by 1, 2;

---clean and update
update bookings_staging_clean 
set 
   check_in_date = case 
	   when nullif(btrim(check_in_date::text), '') is null then null
	   when btrim(check_in_date::text) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
	      then to_char(btrim(check_in_date::text)::date, 'yyyy-mm-dd')
	   when btrim(check_in_date::text) ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
	      then to_char(to_date(btrim(check_in_date::text), 'dd/mm/yyyy'), 'yyyy-mm-dd')
	   when btrim(check_in_date::text) ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
	      then to_char(to_date(btrim(check_in_date::text), 'mm-dd-yyyy'), 'yyyy-mm-dd')
	   else check_in_date::text
   end,
   check_out_date = case
   	   when nullif(btrim(check_out_date::text), '') is null then null
	   when btrim(check_out_date::text) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
	      then to_char(btrim(check_out_date::text)::date, 'yyyy-mm-dd')
	   when btrim(check_out_date::text) ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
	      then to_char(to_date(btrim(check_out_date::text), 'dd/mm/yyyy'), 'yyyy-mm-dd')
	   when btrim(check_out_date::text) ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
	      then to_char(to_date(btrim(check_out_date::text), 'mm-dd-yyyy'), 'yyyy-mm-dd')
	   else check_out_date::text
   end;

select booking_id, check_in_date, check_out_date 
from bookings_staging_clean 
where (
   nullif(btrim(check_in_date::text), '') is not null 
   and btrim(check_in_date::text) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   )
   or (
   nullif(btrim(check_out_date::text), '') is not null 
   and btrim(check_out_date::text) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   );
 
drop table bookings;

---create bookings table
create table bookings (
  booking_id varchar(20) primary key,
  guest_name text not null,
  guest_phone varchar(10),
  guest_city text,
  guest_nationality text,
  room_no integer not null,
  room_type text not null,
  room_rate_per_night numeric(12,2) not null,
  check_in_date date not null,
  check_out_date date not null,
  nights_stayed integer not null,
  staff_name text not null,
  staff_department text not null,
  staff_salary numeric(12,2),
  payment_method text not null,
  booking_status text not null,
  total_amount numeric(12,2) not null,
  service_used text,
  service_price numeric(12,2),
  guest_rating smallint
  
  check (guest_phone is null or guest_phone ~ '^07[0-9]{8}$'),
  check (room_type in ('Standard', 'Deluxe', 'Suite', 'Penthouse')),
  check (payment_method in ('M-Pesa', 'Cash', 'Card', 'Bank Transfer')),
  check (booking_status in ('Checked Out', 'Cancelled', 'No Show')),
  check (check_out_date > check_in_date),
  check (nights_stayed > 0),
  check (room_rate_per_night > 0),
  check (guest_rating is null or guest_rating between 0 and 10)
);

--solve booking_id issue(std to standard)
select booking_id, room_type as old_value, 'Standard' as proposed_value
from bookings_staging_clean
where upper(btrim(room_type)) = 'STD';

update bookings_staging_clean
set room_type = 'Standard'
where upper(btrim(room_type)) = 'STD';

--check for ant other room types
select distinct room_type
from bookings_staging_clean
where nullif(btrim(room_type), '') is null
   or btrim(room_type) not in ('Standard', 'Deluxe', 'Suite', 'Penthouse');

--solve booking_id issue(dlx to deluxe)
update bookings_staging_clean
set room_type = 'Deluxe'
where btrim(room_type) = 'Dlx';

--check for any room types still outside the allowed list
select distinct room_type
from bookings_staging_clean
where nullif(btrim(room_type), '') is null
   or btrim(room_type) not in ('Standard', 'Deluxe', 'Suite', 'Penthouse');

--solve payment_method issue
update bookings_staging_clean
set payment_method = 'M-Pesa'
where btrim(payment_method) = 'Mpesa';

select distinct payment_method
from bookings_staging_clean
where nullif(btrim(payment_method), '') is null
   or btrim(payment_method) not in ('M-Pesa', 'Cash', 'Card', 'Bank Transfer');

--preview all rows with a missing total
select
    booking_id,
    room_rate_per_night,
    nights_stayed,
    service_price,
    (
        nullif(btrim(room_rate_per_night::text), '')::numeric
        * nullif(btrim(nights_stayed::text), '')::numeric
        + coalesce(nullif(btrim(service_price::text), '')::numeric, 0)
    ) AS proposed_total
from bookings_staging_clean
where nullif(btrim(total_amount::text), '') is null
  and nullif(btrim(room_rate_per_night::text), '') is not null
  and nullif(btrim(nights_stayed::text), '') is not null;

--update missing values
update bookings_staging_clean
set total_amount = (
    nullif(btrim(room_rate_per_night::text), '')::numeric
    * nullif(btrim(nights_stayed::text), '')::numeric
    + coalesce(nullif(btrim(service_price::text), '')::numeric, 0)
)::text
where nullif(btrim(total_amount::text), '') is null
  and nullif(btrim(room_rate_per_night::text), '') is not null
  and nullif(btrim(nights_stayed::text), '') is not null;

--update (25475711) pnone_no to null
update bookings_staging_clean
set guest_phone = NULL
WHERE btrim(guest_phone::text) = '25475711';

--remove duplicates
with ranked as (
    select
        ctid,
        row_number() over (
            partition by booking_id
            order by ctid
        ) as row_num
    from bookings_staging_clean
    where booking_id is not null
)
delete from bookings_staging_clean as b
using ranked as r
where b.ctid = r.ctid
  and r.row_num > 1;

--check that no duplicate booking IDs remain
select booking_id, count(*)
from bookings_staging_clean
group by booking_id
having count(*) > 1;

--load cleaned rows
insert into bookings (
    booking_id, guest_name, guest_phone, guest_city, guest_nationality,
    room_no, room_type, room_rate_per_night, check_in_date, check_out_date,
    nights_stayed, staff_name, staff_department, staff_salary,
    payment_method, booking_status, total_amount, service_used,
    service_price, guest_rating
)
select
    btrim(booking_id),
    btrim(guest_name),
    nullif(btrim(guest_phone), ''),
    nullif(btrim(guest_city), ''),
    nullif(btrim(guest_nationality), ''),
    btrim(room_no)::integer,
    btrim(room_type),
    btrim(room_rate_per_night)::numeric,
    btrim(check_in_date)::date,
    btrim(check_out_date)::date,
    btrim(nights_stayed)::integer,
    btrim(staff_name),
    btrim(staff_department),
    nullif(btrim(staff_salary), '')::numeric,
    btrim(payment_method),
    btrim(booking_status),
    btrim(total_amount)::numeric,
    nullif(btrim(service_used), ''),
    nullif(btrim(service_price), '')::numeric,
    nullif(btrim(guest_rating), '')::smallint
from bookings_staging_clean;

select * from bookings;

--create clean view
create view v_clean_bookings as 
select 
  b.*,
  case 
  	when guest_rating >= 4 then 'Happy'
  	when guest_rating = 3 then 'Neutral'
  	when guest_rating between 1 and 0 then 'Unhappy'
  	else 'No Rating'
  end as sentiment
from bookings as b;

--Analysis queries
---revenue
----revenue and checked-out bookings by month
select 
   date_trunc('month', check_in_date)::date as month,
   count(*) as checked_out_bookings,
   sum(total_amount) as collected_revenue 
from v_clean_bookings 
where booking_status = 'Checked Out' 
group by 1
order by month desc;

----revenue and ratings by room type
select 
   room_type,
   count(*) as bookings,
   count(*) filter(where booking_status = 'Checked Out') as checked_out_bookings,
   sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
   avg(total_amount) filter(where booking_status = 'Checked Out') as avrg_rev_per_checkedout_booking,
   avg(guest_rating) as average_rating
from v_clean_bookings
group by room_type
order by collected_revenue desc;

----revenue by payment method
select
    payment_method,
    count(*) filter(where booking_status = 'Checked Out') as checked_out_bookings,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue
from v_clean_bookings
group by payment_method
order by collected_revenue desc;
  
----revenue pivot by payment method and month
select
    date_trunc('month', check_in_date)::date as month,
    sum(total_amount) filter(where payment_method = 'M-Pesa' and booking_status = 'Checked Out') as mpesa_revenue,
    sum(total_amount) filter(where payment_method = 'Cash' and booking_status = 'Checked Out') as cash_revenue,
    sum(total_amount) filter(where payment_method = 'Card' and booking_status = 'Checked Out') as card_revenue,
    sum(total_amount) filter(where payment_method = 'Bank Transfer' and booking_status = 'Checked Out') as bank_transfer_revenue
from tembo_hotel.v_clean_bookings
group by 1
order by month;

---occupancy
----occupancy and revenue by room type
select
   room_type,
   count(*) as total_bookings,
   sum(nights_stayed) filter(where booking_status = 'Checked Out') as total_nights,
   avg(nights_stayed) filter(where booking_status = 'Checked Out') as avg_nights_per_stay,
   sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
   sum(total_amount) filter(where booking_status = 'Checked Out')
      / nullif(sum(nights_stayed) filter(where booking_status = 'Checked Out'), 0) as revenue_per_night
from v_clean_bookings
group by room_type
order by collected_revenue desc;

----bookings and occupied nights by month
select
    date_trunc('month', check_in_date)::date as month,
    count(*) as total_bookings,
    sum(nights_stayed) filter(where booking_status = 'Checked Out') as occupied_nights
from v_clean_bookings
group by 1
order by month;

----stay length by guest city, for cities with at least 3 checked-out bookings
select
    guest_city,
    avg(nights_stayed) as avg_nights,
    avg(total_amount) as avg_amount,
    count(*) as bookings
from v_clean_bookings
where booking_status = 'Checked Out'
  and guest_city is not null
group by guest_city
having count(*) >= 3
order by avg_nights desc;

---guest insights
----top 5 guest cities
select
    guest_city,
    count(distinct guest_name) as guests,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
    avg(guest_rating) as average_rating
from v_clean_bookings
where guest_city is not null
group by guest_city
order by guests desc
limit 5;

----satisfaction by room type
select
    room_type,
    avg(guest_rating) as average_rating,
    100.0 * count(*) filter(where guest_rating >= 4)
      / nullif(count(guest_rating), 0) as percent_rated_4_or_5
from v_clean_bookings
group by room_type
order by average_rating desc;

----repeat guests
select
    guest_name,
    guest_city,
    count(*) as bookings,
    sum(total_amount) filter(where booking_status = 'Checked Out') as total_spent,
    avg(guest_rating) as average_rating
from v_clean_bookings
group by guest_name, guest_city
having count(*) > 1
order by bookings desc;

----sentiment breakdown
select
    sentiment,
    count(*) as bookings,
    round(100.0 * count(*) / SUM(COUNT(*)) over (), 1) as percent_of_bookings
from v_clean_bookings
group by sentiment
order by bookings desc;

---staff perfomance
----staff bookings, collected revenue, and ratings
select
    staff_name,
    staff_department,
    count(*) as bookings_handled,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
    avg(guest_rating) as average_rating
from v_clean_bookings
group by staff_name, staff_department
order by collected_revenue desc;

----department summary; average salary counts each staff member once
with staff_pay as (
    select distinct staff_name, staff_department, staff_salary
    from v_clean_bookings
),
department_pay as (
    select staff_department, avg(staff_salary) as average_salary,
           count(distinct staff_name) as unique_staff
    from staff_pay
    group by staff_department
),
department_bookings as (
    select staff_department,
           count(*) as total_bookings,
           sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue
    from v_clean_bookings
    group by staff_department
)
select
    b.staff_department,
    b.total_bookings,
    b.collected_revenue,
    p.average_salary,
    p.unique_staff
from department_bookings b
join department_pay p using (staff_department)
order by b.collected_revenue desc;

----staff revenue rank overall and within department
with staff_totals as (
    select
        staff_name,
        staff_department,
        count(*) as total_bookings,
        sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue
    from v_clean_bookings
    group by staff_name, staff_department
)
select
    rank() over (order by collected_revenue desc) as overall_rank,
    rank() over (partition by staff_department order by collected_revenue desc) as department_rank,
    staff_name,
    staff_department,
    total_bookings,
    collected_revenue
from staff_totals
order by collected_revenue desc;

---revenue trends
----month-over-month revenue change
with monthly as (
    select
        date_trunc('month', check_in_date)::date as month,
        sum(total_amount) as revenue
    from v_clean_bookings
    where booking_status = 'Checked Out'
    group by 1
),
with_previous as (
    select month, revenue, lag(revenue) over (order by month) as previous_revenue
    from monthly
)
select
    month,
    revenue,
    previous_revenue,
    revenue - previous_revenue as change_amount,
    round(100.0 * (revenue - previous_revenue) / NULLIF(previous_revenue, 0), 1) as change_percent
from with_previous
order by month;

----running revenue total
with monthly as (
    select date_trunc('month', check_in_date)::date as month, sum(total_amount) as revenue
    from v_clean_bookings
    where booking_status = 'Checked Out'
    group by 1
)
select
    month,
    revenue,
    sum(revenue) over (order by month) as cumulative_revenue
from monthly
order by month;

----three strongest and three weakest months
with monthly as (
    select date_trunc('month', check_in_date)::date as month, SUM(total_amount) as revenue
    from v_clean_bookings
    where booking_status = 'Checked Out'
    group by 1
),
ranked as (
    select
        month,
        revenue,
        rank() over (order by revenue desc) as best_rank,
        rank() over (order by revenue asc) as worst_rank
    from monthly
)
select *
from ranked
where best_rank <= 3 or worst_rank <= 3
order by revenue desc;

---cancellations and lost revenue
----count and percentage by status
select
    booking_status,
    count(*) as bookings,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as percent_of_bookings
from v_clean_bookings
group by booking_status
order by bookings desc;

----cancellation and no-show counts by room type
select
    room_type,
    count(*) as total_bookings,
    count(*) filter(where booking_status = 'Checked Out') as checked_out,
    count(*) filter(where booking_status = 'Cancelled') as cancelled,
    count(*) filter(where booking_status = 'No Show') as no_show,
    round(
        100.0 * count(*) filter(where booking_status = 'Cancelled')
        / nullif(count(*), 0),
        1
    ) as cancellation_rate_percent
from v_clean_bookings
group by room_type
order by cancellation_rate_percent desc;

----compare billed lost revenue with collected revenue
select
    booking_status,
    count(*) as bookings,
    sum(total_amount) as billed_amount
from v_clean_bookings
group by booking_status
order by booking_status;

----cancellations by month
select
    date_trunc('month', check_in_date)::date as month,
    count(*) as cancellations
from v_clean_bookings
where booking_status = 'Cancelled'
group by 1
order by month;

--create views for a dashboard in powerbi
create view v_monthly_revenue as
select
    date_trunc('month', check_in_date)::date as month,
    count(*) filter(where booking_status = 'Checked Out') as checked_out_bookings,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue
from tembo_hotel.bookings
group by 1;

select * from v_monthly_revenue;

create view v_room_performance as
select
    room_type,
    count(*) as total_bookings,
    sum(nights_stayed) filter(where booking_status = 'Checked Out') as total_nights,
    avg(nights_stayed) filter(where booking_status = 'Checked Out') as avg_nights,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
    avg(guest_rating) as average_rating
from tembo_hotel.bookings
group by room_type;

select * from v_room_performance;

create view v_staff_performance as
select
    staff_name,
    staff_department,
    count(*) as bookings_handled,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
    avg(guest_rating) as average_rating
from tembo_hotel.bookings
group by staff_name, staff_department;

select * from v_staff_performance;

create view v_guest_insights as
select
    guest_city,
    count(DISTINCT guest_name) as guests,
    sum(total_amount) filter(where booking_status = 'Checked Out') as collected_revenue,
    avg(guest_rating) as average_rating
from tembo_hotel.bookings
group by guest_city;

select * from v_guest_insights;

create view v_cancellation_analysis as
select
    room_type,
    count(*) as total_bookings,
    count(*) filter(where booking_status = 'Cancelled') as cancelled,
    count(*) filter(where booking_status = 'No Show') as no_show,
    round(
        100.0 * count(*) filter(where booking_status = 'Cancelled')
        / nullif(count(*), 0),
        1
    ) as cancellation_rate_percent
from tembo_hotel.bookings
group by room_type;

select * from v_cancellation_analysis;

--add indexes
create index if not exists indx_bookings_room_no
    on bookings (room_no);

create index if not exists indx_bookings_staff_name
    on bookings (staff_name);

create index if not exists indx_bookings_guest_city
    on bookings (guest_city);

create index if not exists indx_bookings_check_in_date
    on bookings (check_in_date);

create index if not exists indx_bookings_room_type
    on bookings (room_type);

create index if not exists indx_bookings_status
    on bookings (booking_status);

---verify indexes
select tablename, indexname
from pg_indexes
where schemaname = 'tembo_hotel'
order by tablename, indexname;












