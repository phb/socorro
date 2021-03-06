--
-- PostgreSQL database dump
--

-- Dumped from database version 9.0.7
-- Dumped by pg_dump version 9.0.7
-- Started on 2012-04-11 12:47:30 PDT

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- TOC entry 2924 (class 2612 OID 267157)
-- Name: plperl; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plperl;


ALTER PROCEDURAL LANGUAGE plperl OWNER TO postgres;

--
-- TOC entry 2923 (class 2612 OID 11574)
-- Name: plpgsql; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plpgsql;


ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO postgres;

SET search_path = public, pg_catalog;

--
-- TOC entry 2077 (class 0 OID 0)
-- Name: citext; Type: SHELL TYPE; Schema: public; Owner: postgres
--

CREATE TYPE citext;


--
-- TOC entry 974 (class 1255 OID 267069)
-- Dependencies: 9 2077
-- Name: citextin(cstring); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citextin(cstring) RETURNS citext
    LANGUAGE internal IMMUTABLE STRICT
    AS $$textin$$;


ALTER FUNCTION public.citextin(cstring) OWNER TO postgres;

--
-- TOC entry 982 (class 1255 OID 267070)
-- Dependencies: 9 2077
-- Name: citextout(citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citextout(citext) RETURNS cstring
    LANGUAGE internal IMMUTABLE STRICT
    AS $$textout$$;


ALTER FUNCTION public.citextout(citext) OWNER TO postgres;

--
-- TOC entry 985 (class 1255 OID 267071)
-- Dependencies: 9 2077
-- Name: citextrecv(internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citextrecv(internal) RETURNS citext
    LANGUAGE internal STABLE STRICT
    AS $$textrecv$$;


ALTER FUNCTION public.citextrecv(internal) OWNER TO postgres;

--
-- TOC entry 987 (class 1255 OID 267072)
-- Dependencies: 9 2077
-- Name: citextsend(citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citextsend(citext) RETURNS bytea
    LANGUAGE internal STABLE STRICT
    AS $$textsend$$;


ALTER FUNCTION public.citextsend(citext) OWNER TO postgres;

--
-- TOC entry 2076 (class 1247 OID 267068)
-- Dependencies: 985 982 974 987 9
-- Name: citext; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE citext (
    INTERNALLENGTH = variable,
    INPUT = citextin,
    OUTPUT = citextout,
    RECEIVE = citextrecv,
    SEND = citextsend,
    CATEGORY = 'S',
    ALIGNMENT = int4,
    STORAGE = extended
);


ALTER TYPE public.citext OWNER TO postgres;

--
-- TOC entry 2372 (class 1247 OID 531499)
-- Dependencies: 2373 9
-- Name: major_version; Type: DOMAIN; Schema: public; Owner: breakpad_rw
--

CREATE DOMAIN major_version AS text
	CONSTRAINT major_version_check CHECK ((VALUE ~ '^\\d+\\.\\d+'::text));


ALTER DOMAIN public.major_version OWNER TO breakpad_rw;

--
-- TOC entry 2446 (class 1247 OID 880676)
-- Dependencies: 9 845
-- Name: product_info_change; Type: TYPE; Schema: public; Owner: breakpad_rw
--

CREATE TYPE product_info_change AS (
	begin_date date,
	end_date date,
	featured boolean,
	crash_throttle numeric
);


ALTER TYPE public.product_info_change OWNER TO breakpad_rw;

--
-- TOC entry 1387 (class 1247 OID 48821)
-- Dependencies: 9
-- Name: release_enum; Type: TYPE; Schema: public; Owner: breakpad_rw
--

CREATE TYPE release_enum AS ENUM (
    'major',
    'milestone',
    'development'
);


ALTER TYPE public.release_enum OWNER TO breakpad_rw;

--
-- TOC entry 1071 (class 1255 OID 907737)
-- Dependencies: 2923 9
-- Name: add_column_if_not_exists(text, text, text, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION add_column_if_not_exists(coltable text, colname text, declaration text, indexed boolean DEFAULT false) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE dex INT := 1;
	scripts TEXT[] := '{}';
BEGIN
-- this function allows you to send an add column script to the backend 
-- multiple times without erroring.  it checks if the column is already
-- there and also optionally creates and index on it

	PERFORM 1 FROM information_schema.columns
	WHERE table_name = coltable
		AND column_name = colname;
	IF FOUND THEN
		RETURN TRUE;
	END IF;	
	
	scripts := string_to_array(declaration, ';');
	WHILE scripts[dex] IS NOT NULL LOOP
		EXECUTE scripts[dex];
		dex := dex + 1;
	END LOOP;

	IF indexed THEN
		EXECUTE 'CREATE INDEX ' || coltable || '_' || colname || 
			' ON ' || coltable || '(' || colname || ')';
	END IF;
	
	RETURN TRUE;
END;
$$;


ALTER FUNCTION public.add_column_if_not_exists(coltable text, colname text, declaration text, indexed boolean) OWNER TO postgres;

--
-- TOC entry 1098 (class 1255 OID 1183249)
-- Dependencies: 1387 2923 9 1387
-- Name: add_old_release(text, text, release_enum, date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION add_old_release(product_name text, new_version text, release_type release_enum DEFAULT 'major'::release_enum, release_date date DEFAULT ('now'::text)::date, is_featured boolean DEFAULT false) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE last_date DATE;
featured_count INT;
new_id INT;
BEGIN

IF release_type = 'major' THEN
last_date := release_date + ( 18 * 7 );
ELSE
last_date := release_date + ( 9 * 7 );
END IF;

IF is_featured THEN
-- check if we already have 4 featured
SELECT COUNT(*) INTO featured_count
FROM productdims JOIN product_visibility
ON productdims.id = product_visibility.productdims_id
WHERE featured
AND product = product_name
AND end_date >= current_date;

IF featured_count > 4 THEN
-- too many, drop one
UPDATE product_visibility
SET featured = false
WHERE productdims_id = (
SELECT id
FROM productdims
JOIN product_visibility viz2
ON productdims.id = viz2.productdims_id
WHERE product = product_name
AND featured
AND end_date >= current_date
ORDER BY viz2.end_date LIMIT 1
);
END IF;
END IF;

    -- now add it
    
    INSERT INTO productdims ( product, version, branch, release, version_sort )
    VALUES ( product_name, new_version, '2.2', release_type, old_version_sort(new_version) )
    RETURNING id
    INTO new_id;
    
    INSERT INTO product_visibility ( productdims_id, start_date, end_date,
    featured, throttle )
    VALUES ( new_id, release_date, last_date, is_featured, 100 );
    
    RETURN TRUE;
    
END; $$;


ALTER FUNCTION public.add_old_release(product_name text, new_version text, release_type release_enum, release_date date, is_featured boolean) OWNER TO postgres;

--
-- TOC entry 1045 (class 1255 OID 656024)
-- Dependencies: 9
-- Name: aurora_or_nightly(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION aurora_or_nightly(version text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
-- figures out "aurora" or "nightly" from a version string
-- returns ERROR otherwise
SELECT CASE WHEN $1 LIKE '%a1' THEN 'nightly'
	WHEN $1 LIKE '%a2' THEN 'aurora'
	ELSE 'ERROR' END;
$_$;


ALTER FUNCTION public.aurora_or_nightly(version text) OWNER TO postgres;

--
-- TOC entry 1085 (class 1255 OID 907815)
-- Dependencies: 9 2923
-- Name: backfill_adu(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_adu(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
-- stored procudure to delete and replace one day of
-- product_adu, optionally only for a specific product
-- intended to be called by backfill_matviews

DELETE FROM product_adu 
WHERE adu_date = updateday;

PERFORM update_adu(updateday);

RETURN TRUE;
END; $$;


ALTER FUNCTION public.backfill_adu(updateday date) OWNER TO postgres;

--
-- TOC entry 980 (class 1255 OID 231511)
-- Dependencies: 2923 9
-- Name: backfill_all_dups(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_all_dups(start_date timestamp without time zone, end_date timestamp without time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare this_time timestamp;
	dups_found int;
begin

this_time := start_date + interval '1 hour';

	create temporary table new_reports_duplicates (
		uuid text, duplicate_of text, date_processed timestamp )
		on commit drop;

-- fill in duplicates for one-hour windows
-- advancing in 30-minute increments
while this_time <= end_date loop

	dups_found := backfill_reports_duplicates( this_time - INTERVAL '1 hour', this_time);
	
	RAISE INFO '% duplicates found for %',dups_found,this_time;

	this_time := this_time + interval '30 minutes';
	
	-- analyze once per day, just to avoid bad query plans
	IF extract('hour' FROM this_time) = 2 THEN
		analyze reports_duplicates;
	END IF;
	
	truncate new_reports_duplicates;

end loop;

return true;
end; $$;


ALTER FUNCTION public.backfill_all_dups(start_date timestamp without time zone, end_date timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 1092 (class 1255 OID 1101652)
-- Dependencies: 2923 9
-- Name: backfill_correlations(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_correlations(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

PERFORM update_correlations(updateday, false);

RETURN TRUE;
END; $$;


ALTER FUNCTION public.backfill_correlations(updateday date) OWNER TO postgres;

--
-- TOC entry 1077 (class 1255 OID 969740)
-- Dependencies: 9 2923
-- Name: backfill_daily_crashes(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_daily_crashes(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $$
BEGIN
-- VERSION 4
-- deletes and replaces daily_crashes for selected dates
-- now just nests a call to update_daily_crashes

DELETE FROM daily_crashes
WHERE adu_day = updateday;
PERFORM update_daily_crashes(updateday, false);

RETURN TRUE;

END;$$;


ALTER FUNCTION public.backfill_daily_crashes(updateday date) OWNER TO postgres;

--
-- TOC entry 988 (class 1255 OID 1256305)
-- Dependencies: 9 2923
-- Name: backfill_explosiveness(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_explosiveness(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

PERFORM update_explosiveness(updateday, false);

RETURN TRUE;
END; $$;


ALTER FUNCTION public.backfill_explosiveness(updateday date) OWNER TO postgres;

--
-- TOC entry 1081 (class 1255 OID 737985)
-- Dependencies: 2923 9
-- Name: backfill_hang_report(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_hang_report(backfilldate date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
-- delete rows
DELETE FROM daily_hangs
WHERE report_date = backfilldate;

PERFORM update_hang_report(backfilldate, false);
RETURN TRUE;

END;
$$;


ALTER FUNCTION public.backfill_hang_report(backfilldate date) OWNER TO postgres;

--
-- TOC entry 1095 (class 1255 OID 907757)
-- Dependencies: 9 2923
-- Name: backfill_matviews(date, date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_matviews(firstday date, lastday date DEFAULT NULL::date, reportsclean boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE thisday DATE := firstday;
	last_rc timestamptz;
	first_rc timestamptz;
	last_adu DATE;
BEGIN
-- this producedure is meant to be called manually
-- by administrators in order to clear and backfill
-- the various matviews in order to recalculate old
-- data which was erroneous.
-- it requires a start date, and optionally an end date
-- no longer takes a product parameter
-- optionally disable reports_clean backfill
-- since that takes a long time

-- set start date for r_c
first_rc := firstday AT TIME ZONE 'UTC';

-- check parameters
IF firstday > current_date OR lastday > current_date THEN
	RAISE EXCEPTION 'date parameter error: cannot backfill into the future';
END IF;

-- set optional end date
IF lastday IS NULL or lastday = current_date THEN
	last_rc := date_trunc('hour', now()) - INTERVAL '3 hours'; 
ELSE 
	last_rc := ( lastday + 1 ) AT TIME ZONE 'UTC';
END IF;

-- check if lastday is after we have ADU;
-- if so, adjust lastday
SELECT max("date") 
INTO last_adu
FROM raw_adu;

IF lastday > last_adu THEN
	RAISE INFO 'last day of backfill period is after final day of ADU.  adjusting last day to %',last_adu;
	lastday := last_adu;
END IF;
	
-- fill in products
PERFORM update_product_versions();

-- backfill reports_clean.  this takes a while
-- we provide a switch to disable it
IF reportsclean THEN
	RAISE INFO 'backfilling reports_clean';
	PERFORM backfill_reports_clean( first_rc, last_rc );
END IF;

-- loop through the days, backfilling one at a time
WHILE thisday <= lastday LOOP
	RAISE INFO 'backfilling other matviews for %',thisday;
	RAISE INFO 'adu';
	PERFORM backfill_adu(thisday);
	RAISE INFO 'tcbs';
	PERFORM backfill_tcbs(thisday);
	DROP TABLE IF EXISTS new_tcbs;
	RAISE INFO 'daily crashes';
	PERFORM backfill_daily_crashes(thisday);
	RAISE INFO 'signatures';
	PERFORM update_signatures(thisday, FALSE);
	DROP TABLE IF EXISTS new_signatures;
	RAISE INFO 'hang report';
	PERFORM backfill_hang_report(thisday);
	RAISE INFO 'nightly builds';
	PERFORM backfill_nightly_builds(thisday);


	thisday := thisday + 1;

END LOOP;

-- finally rank_compare and correlations, which don't need to be filled in for each day
RAISE INFO 'rank_compare';
PERFORM backfill_rank_compare(lastday);
RAISE INFO 'correlations';
PERFORM backfill_correlations(lastday);

RETURN true;
END; $$;


ALTER FUNCTION public.backfill_matviews(firstday date, lastday date, reportsclean boolean) OWNER TO postgres;

--
-- TOC entry 1094 (class 1255 OID 1142116)
-- Dependencies: 2923 9
-- Name: backfill_nightly_builds(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_nightly_builds(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

DELETE FROM nightly_builds WHERE report_date = updateday;
PERFORM update_nightly_builds(updateday, false);

RETURN TRUE;
END; $$;


ALTER FUNCTION public.backfill_nightly_builds(updateday date) OWNER TO postgres;

--
-- TOC entry 1035 (class 1255 OID 519705)
-- Dependencies: 9 2923
-- Name: backfill_one_day(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_one_day() RETURNS text
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET maintenance_work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $$
declare datematch text;
  reppartition text;
  bkdate date;
begin

  SELECT last_date + 1 INTO bkdate
  FROM last_backfill_temp;

  IF bkdate > '2011-08-04' THEN
    RETURN 'done';
  END IF;

  datematch := to_char(bkdate, 'YYMMDD');

  create temporary table back_one_day
  on commit drop as
  select * from releasechannel_backfill
  where uuid LIKE ( '%' || datematch );

  create index back_one_day_idx ON back_one_day(uuid);

  raise info 'temp table created';

  select relname into reppartition
  from pg_stat_user_tables
  where relname like 'reports_2011%'
    and relname <= ( 'reports_20' || datematch )
  order by relname desc limit 1;

  raise info 'updating %',reppartition;
  
  EXECUTE 'UPDATE ' || reppartition || ' SET release_channel = back_one_day.release_channel
    FROM back_one_day WHERE back_one_day.uuid = ' || reppartition || '.uuid;';

  UPDATE last_backfill_temp SET last_date = bkdate;

  RETURN reppartition;

END; $$;


ALTER FUNCTION public.backfill_one_day() OWNER TO postgres;

--
-- TOC entry 1033 (class 1255 OID 519489)
-- Dependencies: 2923 9
-- Name: backfill_one_day(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_one_day(bkdate date) RETURNS text
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET maintenance_work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $$
declare datematch text;
  reppartition text;
begin

  IF bkdate > '2011-08-04' THEN
    RETURN 'done';
  END IF;

  datematch := to_char(bkdate, 'YYMMDD');

  create temporary table back_one_day
  on commit drop as
  select * from releasechannel_backfill
  where uuid LIKE ( '%' || datematch );

  create index back_one_day_idx ON back_one_day(uuid);

  raise info 'temp table created';

  select relname into reppartition
  from pg_stat_user_tables
  where relname like 'reports_2011%'
    and relname <= ( 'reports_20' || datematch )
  order by relname desc limit 1;

  raise info 'updating %',reppartition;
  
  EXECUTE 'UPDATE ' || reppartition || ' SET release_channel = back_one_day.release_channel
    FROM back_one_day WHERE back_one_day.uuid = ' || reppartition || '.uuid;';

  UPDATE last_backfill_temp SET last_date = bkdate;

  RETURN reppartition;

END; $$;


ALTER FUNCTION public.backfill_one_day(bkdate date) OWNER TO postgres;

--
-- TOC entry 1059 (class 1255 OID 1052945)
-- Dependencies: 9 2923
-- Name: backfill_rank_compare(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_rank_compare(updateday date DEFAULT NULL::date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN

PERFORM update_rank_compare(updateday, false);

RETURN TRUE;
END; $$;


ALTER FUNCTION public.backfill_rank_compare(updateday date) OWNER TO postgres;

--
-- TOC entry 1082 (class 1255 OID 737966)
-- Dependencies: 2923 9
-- Name: backfill_reports_clean(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_reports_clean(begin_time timestamp with time zone, end_time timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
-- administrative utility for backfilling reports_clean to the selected date
-- intended to be called on the command line
-- uses a larger cycle (6 hours) if we have to backfill several days of data
-- note that this takes timestamptz as parameters
-- otherwise call backfill_reports_clean_by_date.
DECLARE cyclesize INTERVAL := '1 hour';
	stop_time timestamptz;
	cur_time timestamptz := begin_time;
BEGIN
	IF ( COALESCE(end_time, now()) - begin_time ) > interval '15 hours' THEN
		cyclesize := '6 hours';
	END IF;
	
	IF stop_time IS NULL THEN
	-- if no end time supplied, then default to three hours ago
	-- on the hour
		stop_time := ( date_trunc('hour', now()) - interval '3 hours' );
	END IF;
	
	WHILE cur_time < stop_time LOOP
		IF cur_time + cyclesize > stop_time THEN
			cyclesize = stop_time - cur_time;
		END IF;
		
		RAISE INFO 'backfilling % of reports_clean starting at %',cyclesize,cur_time;
		
		DELETE FROM reports_clean 
		WHERE date_processed >= cur_time 
			AND date_processed < ( cur_time + cyclesize );
		
		DELETE FROM reports_user_info
		WHERE date_processed >= cur_time 
			AND date_processed < ( cur_time + cyclesize );
		
		PERFORM update_reports_clean( cur_time, cyclesize, false );
		
		cur_time := cur_time + cyclesize;
	END LOOP;
	
	RETURN TRUE;
END;$$;


ALTER FUNCTION public.backfill_reports_clean(begin_time timestamp with time zone, end_time timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 981 (class 1255 OID 231512)
-- Dependencies: 2923 9
-- Name: backfill_reports_duplicates(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_reports_duplicates(start_time timestamp without time zone, end_time timestamp without time zone) RETURNS integer
    LANGUAGE plpgsql
    SET work_mem TO '256MB'
    SET temp_buffers TO '128MB'
    AS $$
declare new_dups INT;
begin

-- create a temporary table with the new duplicates
-- for the hour
-- this query contains the duplicate-finding algorithm
-- so it will probably change frequently

insert into new_reports_duplicates
select follower.uuid as uuid,
	leader.uuid as duplicate_of,
	follower.date_processed
from
(  
select uuid,
    install_age,
    uptime,
    client_crash_date,
    date_processed,
  first_value(uuid)
  over ( partition by
            product,
            version,
            build,
            signature,
            cpu_name,
            cpu_info,
            os_name,
            os_version,
            address,
            topmost_filenames,
            reason,
            app_notes,
            url
         order by
            client_crash_date,
            uuid
        ) as leader_uuid
   from reports
   where date_processed BETWEEN start_time AND end_time
 ) as follower
JOIN 
  ( select uuid, install_age, uptime, client_crash_date
    FROM reports
    where date_processed BETWEEN start_time AND end_time ) as leader
  ON follower.leader_uuid = leader.uuid
WHERE ( same_time_fuzzy(leader.client_crash_date, follower.client_crash_date, 
                  leader.uptime, follower.uptime) 
		  OR follower.uptime < 60 
  	  )
  AND
	same_time_fuzzy(leader.client_crash_date, follower.client_crash_date, 
                  leader.install_age, follower.install_age)
  AND follower.uuid <> leader.uuid;
  
-- insert a copy of the leaders
  
insert into new_reports_duplicates
select uuid, uuid, date_processed
from reports
where uuid IN ( select duplicate_of 
	from new_reports_duplicates )
	and date_processed BETWEEN start_time AND end_time;
  
analyze new_reports_duplicates;

select count(*) into new_dups from new_reports_duplicates;

-- insert new duplicates into permanent table

insert into reports_duplicates (uuid, duplicate_of, date_processed )
select new_reports_duplicates.* 
from new_reports_duplicates
	left outer join reports_duplicates USING (uuid)
where reports_duplicates.uuid IS NULL;

-- done return number of dups found and exit
RETURN new_dups;
end;$$;


ALTER FUNCTION public.backfill_reports_duplicates(start_time timestamp without time zone, end_time timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 991 (class 1255 OID 833204)
-- Dependencies: 9 2923
-- Name: backfill_signature_counts(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_signature_counts(begindate date, enddate date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE thisdate DATE := begindate;
BEGIN

WHILE thisdate <= enddate LOOP

	RAISE INFO 'backfilling %',thisdate;

	DELETE FROM os_signature_counts WHERE report_date = thisdate;
	DELETE FROM product_signature_counts WHERE report_date = thisdate;
	DELETE FROM uptime_signature_counts WHERE report_date = thisdate;
	PERFORM update_os_signature_counts(thisdate, false);
	PERFORM update_product_signature_counts(thisdate, false);
	PERFORM update_uptime_signature_counts(thisdate, false);
	
	thisdate := thisdate + 1;
	
END LOOP;

RETURN TRUE;
END; $$;


ALTER FUNCTION public.backfill_signature_counts(begindate date, enddate date) OWNER TO postgres;

--
-- TOC entry 1072 (class 1255 OID 969738)
-- Dependencies: 2923 9
-- Name: backfill_tcbs(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION backfill_tcbs(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
-- function for administrative backfilling of TCBS
-- designed to be called by backfill_matviews
DELETE FROM tcbs WHERE report_date = updateday;
PERFORM update_tcbs(updateday, false);

RETURN TRUE;
END;$$;


ALTER FUNCTION public.backfill_tcbs(updateday date) OWNER TO postgres;

--
-- TOC entry 1037 (class 1255 OID 531501)
-- Dependencies: 9
-- Name: build_date(numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION build_date(build_id numeric) RETURNS date
    LANGUAGE sql IMMUTABLE
    AS $_$
-- converts build number to a date
SELECT to_date(substr( $1::text, 1, 8 ),'YYYYMMDD');
$_$;


ALTER FUNCTION public.build_date(build_id numeric) OWNER TO postgres;

--
-- TOC entry 1050 (class 1255 OID 531517)
-- Dependencies: 9
-- Name: build_numeric(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION build_numeric(character varying) RETURNS numeric
    LANGUAGE sql STRICT
    AS $_$
-- safely converts a build number to a numeric type
-- if the build is not a number, returns NULL
SELECT CASE WHEN $1 ~ $x$^\d+$$x$ THEN
	$1::numeric
ELSE
	NULL::numeric
END;$_$;


ALTER FUNCTION public.build_numeric(character varying) OWNER TO postgres;

--
-- TOC entry 1016 (class 1255 OID 63775)
-- Dependencies: 2923 9
-- Name: check_partitions(text[], integer); Type: FUNCTION; Schema: public; Owner: monitoring
--

CREATE FUNCTION check_partitions(tables text[], numpartitions integer, OUT result integer, OUT data text) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE cur_partition TEXT;
partcount INT;
msg TEXT := '';
thistable TEXT;
BEGIN

result := 0;
cur_partition := to_char(now(),'YYYYMMDD');
-- tables := ARRAY['reports','extensions','frames','plugin_reports'];

FOR thistable IN SELECT * FROM unnest(tables) LOOP

SELECT count(*) INTO partcount
FROM pg_stat_user_tables
WHERE relname LIKE ( thistable || '_%' )  
AND relname > ( thistable || '_' || cur_partition );

--RAISE INFO '% : %',thistable,partcount;

IF partcount < numpartitions OR partcount IS NULL THEN 
result := result + 1;
msg := msg || ' ' || thistable;
END IF;

END LOOP;

IF result > 0 THEN
data := 'Some tables have no future partitions:' || msg;
END IF;

RETURN;

END; $$;


ALTER FUNCTION public.check_partitions(tables text[], numpartitions integer, OUT result integer, OUT data text) OWNER TO monitoring;

--
-- TOC entry 992 (class 1255 OID 267074)
-- Dependencies: 2076 9
-- Name: citext(character); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext(character) RETURNS citext
    LANGUAGE internal IMMUTABLE STRICT
    AS $$rtrim1$$;


ALTER FUNCTION public.citext(character) OWNER TO postgres;

--
-- TOC entry 993 (class 1255 OID 267075)
-- Dependencies: 9 2076
-- Name: citext(boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext(boolean) RETURNS citext
    LANGUAGE internal IMMUTABLE STRICT
    AS $$booltext$$;


ALTER FUNCTION public.citext(boolean) OWNER TO postgres;

--
-- TOC entry 994 (class 1255 OID 267076)
-- Dependencies: 2076 9
-- Name: citext(inet); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext(inet) RETURNS citext
    LANGUAGE internal IMMUTABLE STRICT
    AS $$network_show$$;


ALTER FUNCTION public.citext(inet) OWNER TO postgres;

--
-- TOC entry 1001 (class 1255 OID 267097)
-- Dependencies: 2076 2076 9
-- Name: citext_cmp(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_cmp(citext, citext) RETURNS integer
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_cmp';


ALTER FUNCTION public.citext_cmp(citext, citext) OWNER TO postgres;

--
-- TOC entry 995 (class 1255 OID 267085)
-- Dependencies: 2076 9 2076
-- Name: citext_eq(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_eq(citext, citext) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_eq';


ALTER FUNCTION public.citext_eq(citext, citext) OWNER TO postgres;

--
-- TOC entry 1000 (class 1255 OID 267090)
-- Dependencies: 2076 9 2076
-- Name: citext_ge(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_ge(citext, citext) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_ge';


ALTER FUNCTION public.citext_ge(citext, citext) OWNER TO postgres;

--
-- TOC entry 999 (class 1255 OID 267089)
-- Dependencies: 2076 2076 9
-- Name: citext_gt(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_gt(citext, citext) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_gt';


ALTER FUNCTION public.citext_gt(citext, citext) OWNER TO postgres;

--
-- TOC entry 1002 (class 1255 OID 267098)
-- Dependencies: 2076 9
-- Name: citext_hash(citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_hash(citext) RETURNS integer
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_hash';


ALTER FUNCTION public.citext_hash(citext) OWNER TO postgres;

--
-- TOC entry 1004 (class 1255 OID 267112)
-- Dependencies: 9 2076 2076 2076
-- Name: citext_larger(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_larger(citext, citext) RETURNS citext
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_larger';


ALTER FUNCTION public.citext_larger(citext, citext) OWNER TO postgres;

--
-- TOC entry 998 (class 1255 OID 267088)
-- Dependencies: 9 2076 2076
-- Name: citext_le(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_le(citext, citext) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_le';


ALTER FUNCTION public.citext_le(citext, citext) OWNER TO postgres;

--
-- TOC entry 997 (class 1255 OID 267087)
-- Dependencies: 2076 9 2076
-- Name: citext_lt(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_lt(citext, citext) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_lt';


ALTER FUNCTION public.citext_lt(citext, citext) OWNER TO postgres;

--
-- TOC entry 996 (class 1255 OID 267086)
-- Dependencies: 2076 9 2076
-- Name: citext_ne(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_ne(citext, citext) RETURNS boolean
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_ne';


ALTER FUNCTION public.citext_ne(citext, citext) OWNER TO postgres;

--
-- TOC entry 1003 (class 1255 OID 267111)
-- Dependencies: 9 2076 2076 2076
-- Name: citext_smaller(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION citext_smaller(citext, citext) RETURNS citext
    LANGUAGE c IMMUTABLE STRICT
    AS '$libdir/citext', 'citext_smaller';


ALTER FUNCTION public.citext_smaller(citext, citext) OWNER TO postgres;

--
-- TOC entry 1032 (class 1255 OID 737875)
-- Dependencies: 2076 9
-- Name: content_count_state(integer, citext, integer); Type: FUNCTION; Schema: public; Owner: breakpad_rw
--

CREATE FUNCTION content_count_state(running_count integer, process_type citext, crash_count integer) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
-- allows us to do a content crash count
-- horizontally as well as vertically on tcbs
SELECT CASE WHEN $2 = 'content' THEN
  coalesce($3,0) + $1
ELSE
  $1
END; $_$;


ALTER FUNCTION public.content_count_state(running_count integer, process_type citext, crash_count integer) OWNER TO breakpad_rw;

--
-- TOC entry 1052 (class 1255 OID 833156)
-- Dependencies: 2076 9 2923 2076
-- Name: create_os_version_string(citext, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION create_os_version_string(osname citext, major integer, minor integer) RETURNS citext
    LANGUAGE plpgsql STABLE STRICT
    AS $$
DECLARE winversion CITEXT;
BEGIN
	-- small function which produces a user-friendly
	-- string for the operating system and version
	-- if windows, look it up in windows_versions
	IF osname = 'Windows' THEN
		SELECT windows_version_name INTO winversion
		FROM windows_versions
		WHERE major_version = major AND minor_version = minor;
		IF NOT FOUND THEN
			RETURN 'Windows Unknown';
		ELSE
			RETURN winversion;
		END IF;
	ELSEIF osname = 'Mac OS X' THEN
	-- if mac, then concatinate unless the numbers are impossible
		IF major BETWEEN 10 and 11 AND minor BETWEEN 0 and 20 THEN
			RETURN 'OS X ' || major || '.' || minor;
		ELSE
			RETURN 'OS X Unknown';
		END IF;
	ELSE
	-- for other oses, just use the OS name
		RETURN osname;
	END IF;
END; $$;


ALTER FUNCTION public.create_os_version_string(osname citext, major integer, minor integer) OWNER TO postgres;

--
-- TOC entry 1054 (class 1255 OID 722361)
-- Dependencies: 2923 9
-- Name: create_table_if_not_exists(text, text, text, text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION create_table_if_not_exists(tablename text, declaration text, tableowner text DEFAULT ''::text, indexes text[] DEFAULT '{}'::text[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE dex INT := 1;
	scripts TEXT[] := '{}';
	indexname TEXT;
BEGIN
-- this function allows you to send a create table script to the backend 
-- multiple times without erroring.  it checks if the table is already
-- there and also optionally sets the ownership
-- this version of the function also creates indexes from a list of fields
	PERFORM 1 FROM pg_stat_user_tables
	WHERE relname = tablename;
	IF FOUND THEN
		RETURN TRUE;
	ELSE
		scripts := string_to_array(declaration, ';');
		WHILE scripts[dex] IS NOT NULL LOOP
			EXECUTE scripts[dex];
			dex := dex + 1;
		END LOOP;
	END IF;
	
	IF tableowner <> '' THEN
		EXECUTE 'ALTER TABLE ' || tablename || ' OWNER TO ' || tableowner;
	END IF;
	
	dex := 1;
	
	WHILE indexes[dex] IS NOT NULL LOOP
		indexname := replace( indexes[dex], ',', '_' );
		indexname := replace ( indexname, ' ', '' );
		EXECUTE 'CREATE INDEX ' || tablename || '_' || indexname || 
			' ON ' || tablename || '(' || indexes[dex] || ')';
		dex := dex + 1;
	END LOOP;
	
	EXECUTE 'ANALYZE ' || tablename;
	
	RETURN TRUE;
END;
$$;


ALTER FUNCTION public.create_table_if_not_exists(tablename text, declaration text, tableowner text, indexes text[]) OWNER TO postgres;

--
-- TOC entry 1083 (class 1255 OID 833205)
-- Dependencies: 2923 2076 9
-- Name: create_weekly_partition(citext, date, text, text, text[], text[], text[], boolean, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION create_weekly_partition(tablename citext, theweek date, partcol text DEFAULT 'date_processed'::text, tableowner text DEFAULT ''::text, uniques text[] DEFAULT '{}'::text[], indexes text[] DEFAULT '{}'::text[], fkeys text[] DEFAULT '{}'::text[], is_utc boolean DEFAULT false, timetype text DEFAULT 'TIMESTAMP'::text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE dex INT := 1;
	thispart TEXT;
	zonestring TEXT := '';
	fkstring TEXT;
BEGIN
-- this function allows you to create a new weekly partition
-- of an existing master table.  it checks if the table is already
-- there and also optionally sets the ownership
-- this version of the function also creates indexes from a list of fields
-- currently only handles single-column indexes and unique declarations
-- supports date, timestamp, timestamptz/utc through the various options

	thispart := tablename || '_' || to_char(theweek, 'YYYYMMDD');
	
	PERFORM 1 FROM pg_stat_user_tables
	WHERE relname = thispart;
	IF FOUND THEN
		RETURN TRUE;
	END IF;
	
	IF is_utc THEN
		timetype := ' TIMESTAMP';
		zonestring := ' AT TIME ZONE UTC ';
	END IF;
	
	EXECUTE 'CREATE TABLE ' || thispart || ' ( CONSTRAINT ' || thispart 
		|| '_date_check CHECK ( ' || partcol || ' BETWEEN ' 
		|| timetype || ' ' || quote_literal(to_char(theweek, 'YYYY-MM-DD'))
		|| ' AND ' || timetype || ' ' 
		|| quote_literal(to_char(theweek + 7, 'YYYY-MM-DD'))
		|| ' ) ) INHERITS ( ' || tablename || ');';
	
	IF tableowner <> '' THEN
		EXECUTE 'ALTER TABLE ' || thispart || ' OWNER TO ' || tableowner;
	END IF;
	
	dex := 1;
	WHILE uniques[dex] IS NOT NULL LOOP
		EXECUTE 'CREATE UNIQUE INDEX ' || thispart || '_'
		|| regexp_replace(uniques[dex], $$[,\s]+$$, '_', 'g') 
		|| ' ON ' || thispart || '(' || uniques[dex] || ')';
		dex := dex + 1;
	END LOOP;
	
	dex := 1;
	WHILE indexes[dex] IS NOT NULL LOOP
		EXECUTE 'CREATE INDEX ' || thispart || '_' 
		|| regexp_replace(indexes[dex], $$[,\s]+$$, '_', 'g') 
		|| ' ON ' || thispart || '(' || indexes[dex] || ')';
		dex := dex + 1;
	END LOOP;
	
	dex := 1;
	WHILE fkeys[dex] IS NOT NULL LOOP
		fkstring := regexp_replace(fkeys[dex], 'WEEKNUM', to_char(theweek, 'YYYYMMDD'), 'g');
		EXECUTE 'ALTER TABLE ' || thispart || ' ADD CONSTRAINT ' 
			|| thispart || '_fk_' || dex || ' FOREIGN KEY '
			|| fkstring || ' ON DELETE CASCADE ON UPDATE CASCADE';
		dex := dex + 1;
	END LOOP;
	
	RETURN TRUE;
END;
$_$;


ALTER FUNCTION public.create_weekly_partition(tablename citext, theweek date, partcol text, tableowner text, uniques text[], indexes text[], fkeys text[], is_utc boolean, timetype text) OWNER TO postgres;

--
-- TOC entry 1043 (class 1255 OID 532060)
-- Dependencies: 9
-- Name: daily_crash_code(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION daily_crash_code(process_type text, hangid text) RETURNS character
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT CASE
	WHEN $1 ILIKE 'content' THEN 'T'
	WHEN ( $1 IS NULL OR $1 ILIKE 'browser' ) AND $2 IS NULL THEN 'C'
	WHEN ( $1 IS NULL OR $1 ILIKE 'browser' ) AND $2 IS NOT NULL THEN 'c'
	WHEN $1 ILIKE 'plugin' AND $2 IS NULL THEN 'P'
	WHEN $1 ILIKE 'plugin' AND $2 IS NOT NULL THEN 'p'
	ELSE 'C'
	END
$_$;


ALTER FUNCTION public.daily_crash_code(process_type text, hangid text) OWNER TO postgres;

--
-- TOC entry 1049 (class 1255 OID 726221)
-- Dependencies: 2923 9
-- Name: drop_old_partitions(text, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION drop_old_partitions(mastername text, cutoffdate date) RETURNS boolean
    LANGUAGE plpgsql
    AS $_X$
DECLARE tabname TEXT;
	listnames TEXT;
BEGIN
listnames := $q$SELECT relname FROM pg_stat_user_tables
		WHERE relname LIKE '$q$ || mastername || $q$_%' 
		AND relname < '$q$ || mastername || '_' 
		|| to_char(cutoffdate, 'YYYYMMDD') || $q$'$q$;

IF try_lock_table(mastername,'ACCESS EXCLUSIVE') THEN
	FOR tabname IN EXECUTE listnames LOOP
		
		EXECUTE 'DROP TABLE ' || tabname;
		
	END LOOP;
ELSE
	RAISE EXCEPTION 'Unable to lock table plugin_reports; try again later';
END IF;
RETURN TRUE;
END;
$_X$;


ALTER FUNCTION public.drop_old_partitions(mastername text, cutoffdate date) OWNER TO postgres;

--
-- TOC entry 1056 (class 1255 OID 880685)
-- Dependencies: 2076 9 2923
-- Name: edit_product_info(integer, citext, text, text, date, date, boolean, numeric, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION edit_product_info(prod_id integer, prod_name citext, prod_version text, prod_channel text, begin_visibility date, end_visibility date, is_featured boolean, crash_throttle numeric, user_name text DEFAULT ''::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE which_t text;
	new_id INT;
	oldrec product_info_change;
	newrec product_info_change;
-- this function allows the admin UI to edit product and version
-- information regardless of which table it appears in
-- currently editing the new products is limited to
-- visibility dates and featured because of the need to supply
-- build numbers, and that we're not sure it will ever
-- be required.
-- does not validate required fields or duplicates
-- trusting to the python code and table constraints to do that

-- will be phased out when we can ignore the old productdims

BEGIN

IF prod_id IS NULL THEN
-- new entry
-- adding rows is only allowed to the old table since the new
-- table is populated automatically
-- see if this is supposed to be in the new table and error out
	PERFORM 1
	FROM products
	WHERE product_name = prod_name
		AND major_version_sort(prod_version) >= major_version_sort(rapid_release_version);
	IF FOUND AND prod_version NOT LIKE '%a%' THEN
		RAISE EXCEPTION 'Product % version % will be automatically updated by the new system.  As such, you may not add this product & version manually.',prod_name,prod_version;
	ELSE

		INSERT INTO productdims ( product, version, branch, release )
		VALUES ( prod_name, prod_version, '2.2',
			CASE WHEN prod_channel ILIKE 'beta' THEN 'milestone'::release_enum
				WHEN prod_channel ILIKE 'aurora' THEN 'development'::release_enum
				WHEN prod_channel ILIKE 'nightly' THEN 'development'::release_enum
				ELSE 'major' END )
		RETURNING id
		INTO new_id;

		INSERT INTO product_visibility ( productdims_id, start_date, end_date, featured, throttle )
		VALUES ( new_id, begin_visibility, end_visibility, is_featured, crash_throttle );

	END IF;

ELSE

-- first, find out whether we're dealing with the old or new table
	SELECT which_table INTO which_t
	FROM product_info WHERE product_version_id = prod_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'No product with that ID was found.  Database Error.';
	END IF;

	IF which_t = 'new' THEN
		-- note that changes to the product name or version will be ignored
		-- only changes to featured and visibility dates will be taken
		
		-- first we're going to log this since we've had some issues
		-- and we want to track updates
		INSERT INTO product_info_changelog (
			product_version_id, user_name, changed_on,
			oldrec, newrec )
		SELECT prod_id, user_name, now(),
			row( build_date, sunset_date,
				featured_version, throttle )::product_info_change,
			row( begin_visibility, end_visibility, 
				is_featured, crash_throttle/100 )::product_info_change
		FROM product_versions JOIN product_release_channels
			ON product_versions.product_name = product_release_channels.product_name
			AND product_versions.build_type = product_release_channels.release_channel
		WHERE product_version_id = prod_id;
		
		-- then update
		UPDATE product_versions SET
			featured_version = is_featured,
			build_date = begin_visibility,
			sunset_date = end_visibility
		WHERE product_version_id = prod_id;

		UPDATE product_release_channels
		SET throttle = crash_throttle / 100
		WHERE product_name = prod_name
			AND release_channel = prod_channel;

		new_id := prod_id;
	ELSE
		UPDATE productdims SET
			product = prod_name,
			version = prod_version,
			release = ( CASE WHEN prod_channel ILIKE 'beta' THEN 'milestone'::release_enum
				WHEN prod_channel ILIKE 'aurora' THEN 'development'::release_enum
				WHEN prod_channel ILIKE 'nightly' THEN 'development'::release_enum
				ELSE 'major' END )
		WHERE id = prod_id;

		UPDATE product_visibility SET
			featured = is_featured,
			start_date = begin_visibility,
			end_date = end_visibility,
			throttle = crash_throttle
		WHERE productdims_id = prod_id;

		new_id := prod_id;
	END IF;
END IF;

RETURN new_id;
END; $$;


ALTER FUNCTION public.edit_product_info(prod_id integer, prod_name citext, prod_version text, prod_channel text, begin_visibility date, end_visibility date, is_featured boolean, crash_throttle numeric, user_name text) OWNER TO postgres;

--
-- TOC entry 1069 (class 1255 OID 1101427)
-- Dependencies: 9
-- Name: get_cores(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_cores(cpudetails text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT substring($1 from $x$\| (\d+)$$x$)::INT;
$_$;


ALTER FUNCTION public.get_cores(cpudetails text) OWNER TO postgres;

--
-- TOC entry 1080 (class 1255 OID 1220963)
-- Dependencies: 2076 9 2078
-- Name: get_product_version_ids(citext, citext[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION get_product_version_ids(product citext, VARIADIC versions citext[]) RETURNS integer[]
    LANGUAGE sql
    AS $_$
SELECT array_agg(product_version_id) 
FROM product_versions
	WHERE product_name = $1
	AND version_string = ANY ( $2 );
$_$;


ALTER FUNCTION public.get_product_version_ids(product citext, VARIADIC versions citext[]) OWNER TO postgres;

--
-- TOC entry 1068 (class 1255 OID 969737)
-- Dependencies: 9
-- Name: initcap(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION initcap(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT upper(substr($1,1,1)) || substr($1,2);
$_$;


ALTER FUNCTION public.initcap(text) OWNER TO postgres;

--
-- TOC entry 984 (class 1255 OID 52127)
-- Dependencies: 2923 9
-- Name: last_record(text); Type: FUNCTION; Schema: public; Owner: monitoring
--

CREATE FUNCTION last_record(tablename text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare curdate timestamp;
  resdate timestamp;
  ressecs integer;
begin

CASE WHEN tablename = 'reports' THEN
  curdate:= now() - INTERVAL '3 days';
  EXECUTE 'SELECT max(date_processed)
  FROM reports
  WHERE date_processed > ' || 
        quote_literal(to_char(curdate, 'YYYY-MM-DD')) 
        || ' and date_processed < ' ||
        quote_literal(to_char(curdate + INTERVAL '4 days','YYYY-MM-DD'))
    INTO resdate;
  IF resdate IS NULL THEN
     resdate := curdate;
  END IF;
WHEN tablename = 'top_crashes_by_signature' THEN
  SELECT max(window_end)
  INTO resdate
  FROM top_crashes_by_signature;
WHEN tablename = 'top_crashes_by_url' THEN
  SELECT max(window_end)
  INTO resdate
  FROM top_crashes_by_url;
ELSE
  resdate:= null;
END CASE;

ressecs := round(EXTRACT('epoch' FROM ( now() - resdate )))::INT;

RETURN ressecs;

END;$$;


ALTER FUNCTION public.last_record(tablename text) OWNER TO monitoring;

--
-- TOC entry 979 (class 1255 OID 48826)
-- Dependencies: 9 2923
-- Name: log_priorityjobs(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION log_priorityjobs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare arewelogging boolean;
begin
SELECT log_jobs INTO arewelogging
FROM priorityjobs_logging_switch;
IF arewelogging THEN 
INSERT INTO priorityjobs_log VALUES ( NEW.uuid );
END IF;
RETURN NEW;
end; $$;


ALTER FUNCTION public.log_priorityjobs() OWNER TO postgres;

--
-- TOC entry 1038 (class 1255 OID 531505)
-- Dependencies: 2372 9
-- Name: major_version(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION major_version(version text) RETURNS major_version
    LANGUAGE sql IMMUTABLE
    AS $_$
-- turns a version string into a major version
-- i.e. "6.0a2" into "6.0"
SELECT substring($1 from $x$^(\d+.\d+)$x$)::major_version;
$_$;


ALTER FUNCTION public.major_version(version text) OWNER TO postgres;

--
-- TOC entry 1042 (class 1255 OID 531512)
-- Dependencies: 9
-- Name: major_version_sort(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION major_version_sort(version text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
-- converts a major_version string into a padded,
-- sortable string
select version_sort_digit( substring($1 from $x$^(\d+)$x$) )
	|| version_sort_digit( substring($1 from $x$^\d+\.(\d+)$x$) );
$_$;


ALTER FUNCTION public.major_version_sort(version text) OWNER TO postgres;

--
-- TOC entry 1055 (class 1255 OID 880661)
-- Dependencies: 9
-- Name: old_version_sort(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION old_version_sort(vers text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT to_char( matched[1]::int, 'FM000' )
	|| to_char( matched[2]::int, 'FM000' )
	|| to_char( coalesce( matched[4]::int, 0 ), 'FM000' )
	|| CASE WHEN matched[3] <> '' THEN 'b'
		WHEN matched[5] <> '' THEN 'b'
		ELSE 'z' END
	|| '000'
FROM ( SELECT regexp_matches($1,
$x$^(\d+)[^\d]*\.(\d+)([a-z]?)[^\.]*(?:\.(\d+))?([a-z]?).*$$x$) as matched) as match 
LIMIT 1;
$_$;


ALTER FUNCTION public.old_version_sort(vers text) OWNER TO postgres;

--
-- TOC entry 1061 (class 1255 OID 722350)
-- Dependencies: 9
-- Name: pacific2ts(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION pacific2ts(timestamp with time zone) RETURNS timestamp without time zone
    LANGUAGE sql STABLE
    SET "TimeZone" TO 'America/Los_Angeles'
    AS $_$
SELECT $1::timestamp;
$_$;


ALTER FUNCTION public.pacific2ts(timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 983 (class 1255 OID 176629)
-- Dependencies: 9
-- Name: pg_stat_statements(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION pg_stat_statements(OUT userid oid, OUT dbid oid, OUT query text, OUT calls bigint, OUT total_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint) RETURNS SETOF record
    LANGUAGE c
    AS '$libdir/pg_stat_statements', 'pg_stat_statements';


ALTER FUNCTION public.pg_stat_statements(OUT userid oid, OUT dbid oid, OUT query text, OUT calls bigint, OUT total_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint) OWNER TO postgres;

--
-- TOC entry 986 (class 1255 OID 176628)
-- Dependencies: 9
-- Name: pg_stat_statements_reset(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION pg_stat_statements_reset() RETURNS void
    LANGUAGE c
    AS '$libdir/pg_stat_statements', 'pg_stat_statements_reset';


ALTER FUNCTION public.pg_stat_statements_reset() OWNER TO postgres;

--
-- TOC entry 1040 (class 1255 OID 523708)
-- Dependencies: 2076 9
-- Name: plugin_count_state(integer, citext, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION plugin_count_state(running_count integer, process_type citext, crash_count integer) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
-- allows us to do a plugn count horizontally
-- as well as vertically on tcbs
SELECT CASE WHEN $2 = 'plugin' THEN
  coalesce($3,0) + $1
ELSE
  $1
END; $_$;


ALTER FUNCTION public.plugin_count_state(running_count integer, process_type citext, crash_count integer) OWNER TO postgres;

--
-- TOC entry 1027 (class 1255 OID 267231)
-- Dependencies: 9 2923
-- Name: product_version_sort_number(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION product_version_sort_number(sproduct text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
-- reorders the product-version list for a specific
-- product after an update
-- we just reorder the whole group rather than doing
-- something more fine-tuned because it's actually less
-- work for the database and more foolproof.

UPDATE productdims SET sort_key = new_sort
FROM  ( SELECT product, version, 
row_number() over ( partition by product
order by sec1_num1 ASC NULLS FIRST,
sec1_string1 ASC NULLS LAST,
sec1_num2 ASC NULLS FIRST,
sec1_string2 ASC NULLS LAST,
sec1_num1 ASC NULLS FIRST,
sec1_string1 ASC NULLS LAST,
sec1_num2 ASC NULLS FIRST,
sec1_string2 ASC NULLS LAST,
sec1_num1 ASC NULLS FIRST,
sec1_string1 ASC NULLS LAST,
sec1_num2 ASC NULLS FIRST,
sec1_string2 ASC NULLS LAST,
extra ASC NULLS FIRST)
as new_sort
 FROM productdims_version_sort
 WHERE product = sproduct )
AS product_resort
WHERE productdims.product = product_resort.product
AND productdims.version = product_resort.version
AND ( sort_key <> new_sort OR sort_key IS NULL );

RETURN TRUE;
END;$$;


ALTER FUNCTION public.product_version_sort_number(sproduct text) OWNER TO postgres;

--
-- TOC entry 1013 (class 1255 OID 267139)
-- Dependencies: 2076 2076 9
-- Name: regexp_matches(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_matches(citext, citext) RETURNS text[]
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_matches( $1::pg_catalog.text, $2::pg_catalog.text, 'i' );
$_$;


ALTER FUNCTION public.regexp_matches(citext, citext) OWNER TO postgres;

--
-- TOC entry 1014 (class 1255 OID 267140)
-- Dependencies: 2076 9 2076
-- Name: regexp_matches(citext, citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_matches(citext, citext, text) RETURNS text[]
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_matches( $1::pg_catalog.text, $2::pg_catalog.text, CASE WHEN pg_catalog.strpos($3, 'c') = 0 THEN  $3 || 'i' ELSE $3 END );
$_$;


ALTER FUNCTION public.regexp_matches(citext, citext, text) OWNER TO postgres;

--
-- TOC entry 1015 (class 1255 OID 267141)
-- Dependencies: 9 2076 2076
-- Name: regexp_replace(citext, citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_replace(citext, citext, text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_replace( $1::pg_catalog.text, $2::pg_catalog.text, $3, 'i');
$_$;


ALTER FUNCTION public.regexp_replace(citext, citext, text) OWNER TO postgres;

--
-- TOC entry 1017 (class 1255 OID 267142)
-- Dependencies: 2076 2076 9
-- Name: regexp_replace(citext, citext, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_replace(citext, citext, text, text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_replace( $1::pg_catalog.text, $2::pg_catalog.text, $3, CASE WHEN pg_catalog.strpos($4, 'c') = 0 THEN  $4 || 'i' ELSE $4 END);
$_$;


ALTER FUNCTION public.regexp_replace(citext, citext, text, text) OWNER TO postgres;

--
-- TOC entry 1018 (class 1255 OID 267143)
-- Dependencies: 2076 9 2076
-- Name: regexp_split_to_array(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_split_to_array(citext, citext) RETURNS text[]
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_split_to_array( $1::pg_catalog.text, $2::pg_catalog.text, 'i' );
$_$;


ALTER FUNCTION public.regexp_split_to_array(citext, citext) OWNER TO postgres;

--
-- TOC entry 1019 (class 1255 OID 267144)
-- Dependencies: 2076 9 2076
-- Name: regexp_split_to_array(citext, citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_split_to_array(citext, citext, text) RETURNS text[]
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_split_to_array( $1::pg_catalog.text, $2::pg_catalog.text, CASE WHEN pg_catalog.strpos($3, 'c') = 0 THEN  $3 || 'i' ELSE $3 END );
$_$;


ALTER FUNCTION public.regexp_split_to_array(citext, citext, text) OWNER TO postgres;

--
-- TOC entry 1020 (class 1255 OID 267145)
-- Dependencies: 2076 9 2076
-- Name: regexp_split_to_table(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_split_to_table(citext, citext) RETURNS SETOF text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_split_to_table( $1::pg_catalog.text, $2::pg_catalog.text, 'i' );
$_$;


ALTER FUNCTION public.regexp_split_to_table(citext, citext) OWNER TO postgres;

--
-- TOC entry 1021 (class 1255 OID 267146)
-- Dependencies: 2076 2076 9
-- Name: regexp_split_to_table(citext, citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION regexp_split_to_table(citext, citext, text) RETURNS SETOF text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_split_to_table( $1::pg_catalog.text, $2::pg_catalog.text, CASE WHEN pg_catalog.strpos($3, 'c') = 0 THEN  $3 || 'i' ELSE $3 END );
$_$;


ALTER FUNCTION public.regexp_split_to_table(citext, citext, text) OWNER TO postgres;

--
-- TOC entry 1023 (class 1255 OID 267148)
-- Dependencies: 9 2076 2076 2076
-- Name: replace(citext, citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION replace(citext, citext, citext) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.regexp_replace( $1::pg_catalog.text, pg_catalog.regexp_replace($2::pg_catalog.text, '([^a-zA-Z_0-9])', E'\\\\\\1', 'g'), $3::pg_catalog.text, 'gi' );
$_$;


ALTER FUNCTION public.replace(citext, citext, citext) OWNER TO postgres;

--
-- TOC entry 1034 (class 1255 OID 833146)
-- Dependencies: 2923 9
-- Name: reports_clean_done(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION reports_clean_done(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
-- this function checks that reports_clean has been updated
-- all the way to the last hour of the UTC day
BEGIN

PERFORM 1 
	FROM reports_clean
	WHERE date_processed BETWEEN ( ( updateday::timestamp at time zone 'utc' ) + interval '23 hours' )
		AND ( ( updateday::timestamp at time zone 'utc' ) + interval '1 day' )
	LIMIT 1;
IF FOUND THEN
	RETURN TRUE;
ELSE
	RETURN FALSE;
END IF;
END; $$;


ALTER FUNCTION public.reports_clean_done(updateday date) OWNER TO postgres;

--
-- TOC entry 1090 (class 1255 OID 737962)
-- Dependencies: 2923 9
-- Name: reports_clean_weekly_partition(timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION reports_clean_weekly_partition(this_date timestamp with time zone, which_table text) RETURNS text
    LANGUAGE plpgsql
    SET "TimeZone" TO 'UTC'
    AS $_$
-- this function, meant to be called internally
-- checks if the correct reports_clean or reports_user_info partition exists
-- otherwise it creates it
-- returns the name of the partition
declare this_part text;
	begin_week text;
	end_week text;
	rc_indexes text[];
	dex int := 1;
begin
	this_part := which_table || '_' || to_char(date_trunc('week', this_date), 'YYYYMMDD');
	begin_week := to_char(date_trunc('week', this_date), 'YYYY-MM-DD');
	end_week := to_char(date_trunc('week', this_date) + interval '1 week', 'YYYY-MM-DD');
	
	PERFORM 1
	FROM pg_stat_user_tables
	WHERE relname = this_part;
	IF FOUND THEN
		RETURN this_part;
	END IF;
	
	EXECUTE 'CREATE TABLE ' || this_part || $$
		( CONSTRAINT date_processed_week CHECK ( date_processed >= '$$ || begin_week || $$'::timestamp AT TIME ZONE 'UTC'
			AND date_processed < '$$ || end_week || $$'::timestamp AT TIME ZONE 'UTC' ) )
		INHERITS ( $$ || which_table || $$ );$$;
	EXECUTE 'CREATE UNIQUE INDEX ' || this_part || '_uuid ON ' || this_part || '(uuid);';

	IF which_table = 'reports_clean' THEN

		rc_indexes := ARRAY[ 'date_processed', 'product_version_id', 'os_name', 'os_version_id', 
			'signature_id', 'address_id', 'flash_version_id', 'hang_id', 'process_type', 'release_channel', 'domain_id' ];
			
		EXECUTE 'CREATE INDEX ' || this_part || '_sig_prod_date ON ' || this_part 
			|| '( signature_id, product_version_id, date_processed )';
			
		EXECUTE 'CREATE INDEX ' || this_part || '_arch_cores ON ' || this_part 
			|| '( architecture, cores )';
			
	ELSEIF which_table = 'reports_user_info' THEN
	
		rc_indexes := '{}';
	
	END IF;
	
	WHILE rc_indexes[dex] IS NOT NULL LOOP
		EXECUTE 'CREATE INDEX ' || this_part || '_' || rc_indexes[dex]
			|| ' ON ' || this_part || '(' || rc_indexes[dex] || ');';
		dex := dex + 1;
	END LOOP;
	
	EXECUTE 'ALTER TABLE ' || this_part || ' OWNER TO breakpad_rw';
	
	RETURN this_part;
end;$_$;


ALTER FUNCTION public.reports_clean_weekly_partition(this_date timestamp with time zone, which_table text) OWNER TO postgres;

--
-- TOC entry 989 (class 1255 OID 231532)
-- Dependencies: 9
-- Name: same_time_fuzzy(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION same_time_fuzzy(date1 timestamp with time zone, date2 timestamp with time zone, interval_secs1 integer, interval_secs2 integer) RETURNS boolean
    LANGUAGE sql
    AS $_$
SELECT
-- return true if either interval is null
-- so we don't exclude crashes missing data
CASE WHEN $3 IS NULL THEN
	TRUE
WHEN $4 IS NULL THEN
	TRUE
-- otherwise check that the two timestamp deltas
-- and the two interval deltas are within 60 sec
-- of each other
ELSE
	(
		extract ('epoch' from ( $2 - $1 ) ) -
		( $4 - $3 ) 
	) BETWEEN -60 AND 60
END;
$_$;


ALTER FUNCTION public.same_time_fuzzy(date1 timestamp with time zone, date2 timestamp with time zone, interval_secs1 integer, interval_secs2 integer) OWNER TO postgres;

--
-- TOC entry 1024 (class 1255 OID 267149)
-- Dependencies: 2076 2076 9
-- Name: split_part(citext, citext, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION split_part(citext, citext, integer) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT (pg_catalog.regexp_split_to_array( $1::pg_catalog.text, pg_catalog.regexp_replace($2::pg_catalog.text, '([^a-zA-Z_0-9])', E'\\\\\\1', 'g'), 'i'))[$3];
$_$;


ALTER FUNCTION public.split_part(citext, citext, integer) OWNER TO postgres;

--
-- TOC entry 1022 (class 1255 OID 267147)
-- Dependencies: 9 2076 2076
-- Name: strpos(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION strpos(citext, citext) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.strpos( pg_catalog.lower( $1::pg_catalog.text ), pg_catalog.lower( $2::pg_catalog.text ) );
$_$;


ALTER FUNCTION public.strpos(citext, citext) OWNER TO postgres;

--
-- TOC entry 1044 (class 1255 OID 531513)
-- Dependencies: 9 2076
-- Name: sunset_date(numeric, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION sunset_date(build_id numeric, build_type citext) RETURNS date
    LANGUAGE sql IMMUTABLE
    AS $_$
-- sets a sunset date for visibility
-- based on a build number
-- current spec is 18 weeks for releases
-- 9 weeks for everything else
select ( build_date($1) +
	case when $2 = 'release'
		then interval '18 weeks'
	when $2 = 'ESR'
		then interval '18 weeks'
	else
		interval '9 weeks'
	end ) :: date
$_$;


ALTER FUNCTION public.sunset_date(build_id numeric, build_type citext) OWNER TO postgres;

--
-- TOC entry 1005 (class 1255 OID 267115)
-- Dependencies: 2076 2076 9
-- Name: texticlike(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticlike(citext, citext) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticlike$$;


ALTER FUNCTION public.texticlike(citext, citext) OWNER TO postgres;

--
-- TOC entry 1009 (class 1255 OID 267127)
-- Dependencies: 9 2076
-- Name: texticlike(citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticlike(citext, text) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticlike$$;


ALTER FUNCTION public.texticlike(citext, text) OWNER TO postgres;

--
-- TOC entry 1006 (class 1255 OID 267116)
-- Dependencies: 2076 9 2076
-- Name: texticnlike(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticnlike(citext, citext) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticnlike$$;


ALTER FUNCTION public.texticnlike(citext, citext) OWNER TO postgres;

--
-- TOC entry 1010 (class 1255 OID 267128)
-- Dependencies: 2076 9
-- Name: texticnlike(citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticnlike(citext, text) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticnlike$$;


ALTER FUNCTION public.texticnlike(citext, text) OWNER TO postgres;

--
-- TOC entry 1007 (class 1255 OID 267117)
-- Dependencies: 2076 9 2076
-- Name: texticregexeq(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticregexeq(citext, citext) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticregexeq$$;


ALTER FUNCTION public.texticregexeq(citext, citext) OWNER TO postgres;

--
-- TOC entry 1011 (class 1255 OID 267129)
-- Dependencies: 9 2076
-- Name: texticregexeq(citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticregexeq(citext, text) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticregexeq$$;


ALTER FUNCTION public.texticregexeq(citext, text) OWNER TO postgres;

--
-- TOC entry 1008 (class 1255 OID 267118)
-- Dependencies: 9 2076 2076
-- Name: texticregexne(citext, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticregexne(citext, citext) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticregexne$$;


ALTER FUNCTION public.texticregexne(citext, citext) OWNER TO postgres;

--
-- TOC entry 1012 (class 1255 OID 267130)
-- Dependencies: 2076 9
-- Name: texticregexne(citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION texticregexne(citext, text) RETURNS boolean
    LANGUAGE internal IMMUTABLE STRICT
    AS $$texticregexne$$;


ALTER FUNCTION public.texticregexne(citext, text) OWNER TO postgres;

--
-- TOC entry 1026 (class 1255 OID 267158)
-- Dependencies: 9 2924
-- Name: tokenize_version(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION tokenize_version(version text, OUT s1n1 integer, OUT s1s1 text, OUT s1n2 integer, OUT s1s2 text, OUT s2n1 integer, OUT s2s1 text, OUT s2n2 integer, OUT s2s2 text, OUT s3n1 integer, OUT s3s1 text, OUT s3n2 integer, OUT s3s2 text, OUT ext text) RETURNS record
    LANGUAGE plperl
    AS $_X$
    my $version = shift;
    my @parts = split /[.]/ => $version;
    my $extra;
    if (@parts > 3) {
        $extra = join '.', @parts[3..$#parts];
        @parts = @parts[0..2];
    }

    my @tokens;
    for my $part (@parts) {
        die "$version is not a valid toolkit version" unless $part =~ qr{\A
            ([-]?\d+)                    # number-a
            (?:
                ([-_a-zA-Z]+(?=-|\d|\z)) # string-b
                (?:
                    (-?\d+)              # number-c
                    (?:
                        ([^-*+\s]+)      # string-d
                    |\z)
                |\z)
            |\z)
        \z}x;
        push @tokens, $1, $2, $3, $4;
    }

    die "$version is not a valid toolkit version" unless @tokens;
    my @cols = qw(s1n1 s1s1 s1n2 s1s2 s2n1 s2s1 s2n2 s2s2 s3n1 s3s1 s3n2 s3s2 ext);
    return { ext => $extra, map { $cols[$_] => $tokens[$_] } 0..11 }
$_X$;


ALTER FUNCTION public.tokenize_version(version text, OUT s1n1 integer, OUT s1s1 text, OUT s1n2 integer, OUT s1s2 text, OUT s2n1 integer, OUT s2s1 text, OUT s2n2 integer, OUT s2s2 text, OUT s3n1 integer, OUT s3s1 text, OUT s3n2 integer, OUT s3s2 text, OUT ext text) OWNER TO postgres;

--
-- TOC entry 1070 (class 1255 OID 1159740)
-- Dependencies: 9 2923
-- Name: transform_rules_insert_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION transform_rules_insert_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE order_num INT;
-- this trigger function makes sure that all rules have a unique order
-- within their category, and assigns an order number to new rules
BEGIN
	IF NEW.rule_order IS NULL or NEW.rule_order = 0 THEN
		-- no order supplied, add the rule to the end
		SELECT max(rule_order) 
		INTO order_num
		FROM transform_rules
		WHERE category = NEW.category;
		
		NEW.rule_order := COALESCE(order_num, 0) + 1;
	ELSE
		-- check if there's already a gap there
		PERFORM rule_order 
		FROM transform_rules
		WHERE category = NEW.category
			AND rule_order = NEW.rule_order;
		-- if not, then bump up
		IF FOUND THEN
			UPDATE transform_rules 
			SET rule_order = rule_order + 1
			WHERE category = NEW.category
				AND rule_order = NEW.rule_order;
		END IF;
	END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.transform_rules_insert_order() OWNER TO postgres;

--
-- TOC entry 1074 (class 1255 OID 1159741)
-- Dependencies: 9 2923
-- Name: transform_rules_update_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION transform_rules_update_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	-- if we've changed the order number, or category reorder
	IF NEW.rule_order <> OLD.rule_order 
		OR NEW.category <> OLD.category THEN
				
		-- insert a new gap
		UPDATE transform_rules
		SET rule_order = rule_order + 1
		WHERE category = NEW.category
			AND rule_order = NEW.rule_order
			AND transform_rule_id <> NEW.transform_rule_id;
	
	END IF;	
		
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.transform_rules_update_order() OWNER TO postgres;

--
-- TOC entry 1025 (class 1255 OID 267150)
-- Dependencies: 2076 2076 9
-- Name: translate(citext, citext, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION translate(citext, citext, text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT pg_catalog.translate( pg_catalog.translate( $1::pg_catalog.text, pg_catalog.lower($2::pg_catalog.text), $3), pg_catalog.upper($2::pg_catalog.text), $3);
$_$;


ALTER FUNCTION public.translate(citext, citext, text) OWNER TO postgres;

--
-- TOC entry 1048 (class 1255 OID 726220)
-- Dependencies: 2923 9
-- Name: try_lock_table(text, text, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION try_lock_table(tabname text, mode text DEFAULT 'EXCLUSIVE'::text, attempts integer DEFAULT 20) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
-- this function tries to lock a table
-- in a loop, retrying every 3 seconds for 20 tries
-- until it gets a lock
-- or gives up
-- returns true if the table is locked, false
-- if unable to lock
DECLARE loopno INT := 1;
BEGIN
	WHILE loopno < attempts LOOP
		BEGIN
			EXECUTE 'LOCK TABLE ' || tabname || ' IN ' || mode || ' MODE NOWAIT';
			RETURN TRUE;
		EXCEPTION
			WHEN LOCK_NOT_AVAILABLE THEN
				PERFORM pg_sleep(3);
				CONTINUE;
		END;
	END LOOP;
RETURN FALSE;
END;$$;


ALTER FUNCTION public.try_lock_table(tabname text, mode text, attempts integer) OWNER TO postgres;

--
-- TOC entry 1036 (class 1255 OID 833147)
-- Dependencies: 9
-- Name: tstz_between(timestamp with time zone, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION tstz_between(tstz timestamp with time zone, bdate date, fdate date) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT $1 >= ( $2::timestamp AT TIME ZONE 'UTC' ) 
	AND $1 < ( ( $3 + 1 )::timestamp AT TIME ZONE 'UTC' );
$_$;


ALTER FUNCTION public.tstz_between(tstz timestamp with time zone, bdate date, fdate date) OWNER TO postgres;

--
-- TOC entry 1097 (class 1255 OID 907814)
-- Dependencies: 9 2923
-- Name: update_adu(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_adu(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $$
BEGIN
-- daily batch update procedure to update the
-- adu-product matview, used to power graphs
-- gets its data from raw_adu, which is populated
-- daily by metrics

-- check if raw_adu has been updated.  otherwise, abort.
PERFORM 1 FROM raw_adu
WHERE "date" = updateday
LIMIT 1;

IF NOT FOUND THEN
	IF checkdata THEN
		RAISE EXCEPTION 'raw_adu not updated for %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- check if ADU has already been run for the date
IF checkdata THEN
	PERFORM 1 FROM product_adu
	WHERE adu_date = updateday LIMIT 1;
	
	IF FOUND THEN
		RAISE EXCEPTION 'update_adu has already been run for %', updateday;
	END IF;
END IF;

-- insert releases
-- note that we're now matching against product_guids were we can
-- and that we need to strip the {} out of the guids

INSERT INTO product_adu ( product_version_id, os_name,
		adu_date, adu_count )
SELECT product_version_id, coalesce(os_name,'Unknown') as os,
	updateday,
	coalesce(sum(adu_count), 0)
FROM product_versions
	LEFT OUTER JOIN ( 
		SELECT COALESCE(prodmap.product_name, raw_adu.product_name)::citext
			as product_name, raw_adu.product_version::citext as product_version,
			raw_adu.build_channel::citext as build_channel,
			raw_adu.adu_count,
			os_name_matches.os_name
		FROM raw_adu 
		LEFT OUTER JOIN product_productid_map as prodmap 
			ON raw_adu.product_guid = btrim(prodmap.productid, '{}')
		LEFT OUTER JOIN os_name_matches
    		ON raw_adu.product_os_platform ILIKE os_name_matches.match_string
		WHERE raw_adu.date = updateday
		) as prod_adu
		ON product_versions.product_name = prod_adu.product_name
		AND product_versions.version_string = prod_adu.product_version
		AND product_versions.build_type = prod_adu.build_channel	
WHERE updateday BETWEEN build_date AND ( sunset_date + 1 )
        AND product_versions.build_type IN ('release','nightly','aurora')
GROUP BY product_version_id, os;

-- insert ESRs
-- need a separate query here because the ESR version number doesn't match

INSERT INTO product_adu ( product_version_id, os_name,
		adu_date, adu_count )
SELECT product_version_id, coalesce(os_name,'Unknown') as os,
	updateday,
	coalesce(sum(adu_count), 0)
FROM product_versions
	LEFT OUTER JOIN ( 
		SELECT COALESCE(prodmap.product_name, raw_adu.product_name)::citext
			as product_name, raw_adu.product_version::citext as product_version,
			raw_adu.build_channel::citext as build_channel,
			raw_adu.adu_count,
			os_name_matches.os_name
		FROM raw_adu 
		LEFT OUTER JOIN product_productid_map as prodmap 
			ON raw_adu.product_guid = btrim(prodmap.productid, '{}')
		LEFT OUTER JOIN os_name_matches
    		ON raw_adu.product_os_platform ILIKE os_name_matches.match_string
		WHERE raw_adu.date = updateday
			and raw_adu.build_channel ILIKE 'esr'
		) as prod_adu
		ON product_versions.product_name = prod_adu.product_name
		AND product_versions.version_string 
			=  ( prod_adu.product_version || 'esr' )
		AND product_versions.build_type = prod_adu.build_channel	
WHERE updateday BETWEEN build_date AND ( sunset_date + 1 )
        AND product_versions.build_type = 'ESR'
GROUP BY product_version_id, os;

-- insert betas
-- does not include any missing beta counts; should resolve that later

INSERT INTO product_adu ( product_version_id, os_name,
		adu_date, adu_count )
SELECT product_version_id, coalesce(os_name,'Unknown') as os,
	updateday,
	coalesce(sum(adu_count), 0)
FROM product_versions
	LEFT OUTER JOIN ( 
		SELECT COALESCE(prodmap.product_name, raw_adu.product_name)::citext
			as product_name, raw_adu.product_version::citext as product_version,
			raw_adu.build_channel::citext as build_channel,
			raw_adu.adu_count,
			os_name_matches.os_name,
			build_numeric(raw_adu.build) as build_id
		FROM raw_adu 
		LEFT OUTER JOIN product_productid_map as prodmap 
			ON raw_adu.product_guid = btrim(prodmap.productid, '{}')
		LEFT OUTER JOIN os_name_matches
    		ON raw_adu.product_os_platform ILIKE os_name_matches.match_string
		WHERE raw_adu.date = updateday
			AND raw_adu.build_channel = 'beta'
		) as prod_adu
		ON product_versions.product_name = prod_adu.product_name
		AND product_versions.release_version = prod_adu.product_version
		AND product_versions.build_type = prod_adu.build_channel	
WHERE updateday BETWEEN build_date AND ( sunset_date + 1 )
        AND product_versions.build_type = 'Beta'
        AND EXISTS ( SELECT 1
            FROM product_version_builds
            WHERE product_versions.product_version_id = product_version_builds.product_version_id
              AND product_version_builds.build_id = prod_adu.build_id
            )
GROUP BY product_version_id, os;

-- insert old products

INSERT INTO product_adu ( product_version_id, os_name,
        adu_date, adu_count )
SELECT productdims_id, coalesce(os_name,'Unknown') as os,
	updateday, coalesce(sum(raw_adu.adu_count),0)
FROM productdims
	JOIN product_visibility ON productdims.id = product_visibility.productdims_id
	LEFT OUTER JOIN raw_adu
		ON productdims.product = raw_adu.product_name::citext
		AND productdims.version = raw_adu.product_version::citext
		AND raw_adu.date = updateday
    LEFT OUTER JOIN os_name_matches
    	ON raw_adu.product_os_platform ILIKE os_name_matches.match_string
WHERE updateday BETWEEN ( start_date - interval '1 day' )
	AND ( end_date + interval '1 day' )
GROUP BY productdims_id, os;

RETURN TRUE;
END; $$;


ALTER FUNCTION public.update_adu(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1091 (class 1255 OID 1101651)
-- Dependencies: 2923 9
-- Name: update_correlations(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_correlations(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET client_min_messages TO 'ERROR'
    AS $$
BEGIN
-- this function populates daily matviews
-- for some of the correlation reports
-- depends on reports_clean

-- no need to check if we've been run, since the correlations
-- only hold the last day of data

-- check if reports_clean is complete
IF NOT reports_clean_done(updateday) THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Reports_clean has not been updated to the end of %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- clear the correlations list
-- can't use TRUNCATE here because of locking
DELETE FROM correlations;

--create the correlations list
INSERT INTO correlations ( signature_id, product_version_id,
	os_name, reason_id, crash_count )
SELECT signature_id, product_version_id,
	os_name, reason_id, count(*)
FROM reports_clean
	JOIN product_versions USING ( product_version_id )
WHERE updateday BETWEEN build_date and sunset_date
	and utc_day_is(date_processed, updateday)
GROUP BY product_version_id, os_name, reason_id, signature_id
ORDER BY product_version_id, os_name, reason_id, signature_id;

ANALYZE correlations;

-- create list of UUID-report_id correspondences for the day
CREATE TEMPORARY TABLE uuid_repid
AS
SELECT uuid, id as report_id
FROM reports
WHERE utc_day_is(date_processed, updateday)
ORDER BY uuid, report_id;
CREATE INDEX uuid_repid_key on uuid_repid(uuid, report_id);
ANALYZE uuid_repid;

--create the correlation-addons list
INSERT INTO correlation_addons (
	correlation_id, addon_key, addon_version, crash_count )
SELECT correlation_id, extension_id, extension_version, count(*)
FROM correlations 
	JOIN reports_clean 
		USING ( product_version_id, os_name, reason_id, signature_id )
	JOIN uuid_repid 
		USING ( uuid )
	JOIN extensions 
		USING ( report_id )
	JOIN product_versions 
		USING ( product_version_id )
WHERE utc_day_is(reports_clean.date_processed, updateday)
	AND utc_day_is(extensions.date_processed, updateday)
	AND updateday BETWEEN build_date AND sunset_date
GROUP BY correlation_id, extension_id, extension_version;

ANALYZE correlation_addons;

--create correlations-cores list
INSERT INTO correlation_cores (
	correlation_id, architecture, cores, crash_count )
SELECT correlation_id, architecture, cores, count(*)
FROM correlations 
	JOIN reports_clean 
		USING ( product_version_id, os_name, reason_id, signature_id )
	JOIN product_versions 
		USING ( product_version_id )
WHERE utc_day_is(reports_clean.date_processed, updateday)
	AND updateday BETWEEN build_date AND sunset_date
	AND architecture <> '' AND cores >= 0
GROUP BY correlation_id, architecture, cores;

ANALYZE correlation_cores;

RETURN TRUE;
END; $$;


ALTER FUNCTION public.update_correlations(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1078 (class 1255 OID 969741)
-- Dependencies: 2923 9
-- Name: update_daily_crashes(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_daily_crashes(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $$
BEGIN
-- update the daily crashes summary matview
-- VERSION 4
-- updates daily_crashes for new products using reports_clean
-- instead of using reports

-- apologies for badly written SQL, didn't want to rewrite it all from scratch

-- note: we are currently excluding crashes which are missing an OS_Name from the count

-- check if we've already been run
IF checkdata THEN
	PERFORM 1 FROM daily_crashes
	WHERE adu_day = updateday LIMIT 1;
	IF FOUND THEN
		RAISE EXCEPTION 'daily_crashes has already been run for %', updateday;
	END IF;
END IF;

-- check if reports_clean is updated
IF NOT reports_clean_done(updateday) THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Reports_clean has not been updated to the end of %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- insert old browser crashes
-- for most crashes
INSERT INTO daily_crashes (count, report_type, productdims_id, os_short_name, adu_day)
SELECT COUNT(*) as count, daily_crash_code(process_type, hangid) as crash_code, p.id,
	substring(r.os_name, 1, 3) AS os_short_name,
	updateday
FROM product_visibility cfg
JOIN productdims p on cfg.productdims_id = p.id
JOIN reports r on p.product = r.product AND p.version = r.version
WHERE NOT cfg.ignore AND
	date_processed >= ( updateday::timestamptz )
		AND date_processed < ( updateday + 1 )::timestamptz
	AND updateday BETWEEN cfg.start_date and cfg.end_date
    AND lower(substring(os_name, 1, 3)) IN ('win','lin','mac')
GROUP BY p.id, crash_code, os_short_name;

 -- insert HANGS_NORMALIZED from old data
INSERT INTO daily_crashes (count, report_type, productdims_id, os_short_name, adu_day)
SELECT count(subr.hangid) as count, 'H', subr.prod_id, subr.os_short_name,
	 updateday
FROM (
		   SELECT distinct hangid, p.id AS prod_id, substring(r.os_name, 1, 3) AS os_short_name
		   FROM product_visibility cfg
		   JOIN productdims p on cfg.productdims_id = p.id
		   JOIN reports r on p.product = r.product AND p.version = r.version
		   WHERE NOT cfg.ignore AND
			date_processed >= ( updateday::timestamptz )
				AND date_processed < ( updateday + 1 )::timestamptz
				AND updateday BETWEEN cfg.start_date and cfg.end_date
				AND hangid IS NOT NULL
                AND lower(substring(os_name, 1, 3)) IN ('win','lin','mac')
		 ) AS subr
GROUP BY subr.prod_id, subr.os_short_name;

-- insert crash counts for new products
INSERT INTO daily_crashes (count, report_type, productdims_id, os_short_name, adu_day)
SELECT COUNT(*) as count, daily_crash_code(process_type, hang_id) as crash_code,
	product_version_id, 
	initcap(os_short_name),
	updateday
FROM reports_clean JOIN product_versions USING (product_version_id)
	JOIN os_names USING (os_name)
WHERE utc_day_is(date_processed, updateday)
	AND updateday BETWEEN product_versions.build_date and sunset_date
GROUP BY product_version_id, crash_code, os_short_name;

-- insert normalized hangs for new products
INSERT INTO daily_crashes (count, report_type, productdims_id, os_short_name, adu_day)
SELECT count(DISTINCT hang_id) as count, 'H', 
	product_version_id, initcap(os_short_name),
	updateday
FROM product_versions
	JOIN reports_clean USING ( product_version_id )
	JOIN os_names USING (os_name)
	WHERE utc_day_is(date_processed, updateday)
		AND updateday BETWEEN product_versions.build_date and sunset_date
GROUP BY product_version_id, os_short_name;

ANALYZE daily_crashes;

RETURN TRUE;

END;$$;


ALTER FUNCTION public.update_daily_crashes(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 978 (class 1255 OID 1256303)
-- Dependencies: 9 2923
-- Name: update_explosiveness(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_explosiveness(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET client_min_messages TO 'ERROR'
    AS $$
-- set stats parameters per Kairo
DECLARE 
	-- minimum crashes/mil.adu to show up
	minrate INT := 10;	
	-- minimum comparitor figures if there are no
	-- or very few proir crashes to smooth curves
	-- mostly corresponds to Kairo "clampperadu"
	mindiv_one INT := 30;
	mindiv_three INT := 15;
	mes_edate DATE;
	mes_b3date DATE;
	comp_e1date DATE;
	comp_e3date DATE;
	comp_bdate DATE;
BEGIN
-- this function populates a daily matview
-- for explosiveness
-- depends on tcbs and product_adu

-- check if we've been run
IF checkdata THEN
	PERFORM 1 FROM explosiveness
	WHERE report_date = updateday
	LIMIT 1;
	IF FOUND THEN
		RAISE EXCEPTION 'explosiveness has already been run for %.',updateday;
	END IF;
END IF;

-- check if product_adu and tcbs are updated
PERFORM 1
FROM tcbs JOIN product_adu
   ON tcbs.report_date = product_adu.adu_date
WHERE tcbs.report_date = updateday
LIMIT 1;

IF NOT FOUND THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Either product_adu or tcbs have not been updated to the end of %',updateday;
	ELSE
		RAISE NOTICE 'Either product_adu or tcbs has not been updated, skipping.';
		RETURN TRUE;
	END IF;
END IF;

-- compute dates 
-- note that dates are inclusive
-- last date of measured period
mes_edate := updateday;
-- first date of the measured period for 3-day
mes_b3date := updateday - 2;
-- last date of the comparison period for 1-day
comp_e1date := updateday - 1;
-- last date of the comparison period for 3-day
comp_e3date := mes_b3date - 1;
-- first date of the comparison period
comp_bdate := mes_edate - 9;

-- create oneday temp table
CREATE TEMPORARY TABLE explosive_oneday
ON COMMIT DROP
AS 
WITH adusum AS (
	SELECT adu_date, sum(adu_count) as adu_count,
		( mindiv_one * 1000000::numeric / sum(adu_count)) as mindivisor,
		product_version_id
	FROM product_adu
	WHERE adu_date BETWEEN comp_bdate and mes_edate
		AND adu_count > 0
	GROUP BY adu_date, product_version_id 
),
reportsum AS (
	SELECT report_date, sum(report_count) as report_count,
		product_version_id, signature_id
	FROM tcbs
	WHERE report_date BETWEEN comp_bdate and mes_edate
	GROUP BY report_date, product_version_id, signature_id
),
crash_madu AS (
	SELECT ( report_count * 1000000::numeric ) / adu_count AS crash_madu,
		reportsum.product_version_id, reportsum.signature_id, 
		report_date, mindivisor
	FROM adusum JOIN reportsum
		ON adu_date = report_date
		AND adusum.product_version_id = reportsum.product_version_id
),
sum1day AS ( 
	SELECT product_version_id, signature_id, crash_madu as sum1day,
		mindivisor
	FROM crash_madu
	WHERE report_date = mes_edate
	AND crash_madu > 10
),
agg9day AS (
	SELECT product_version_id, signature_id,
		AVG(crash_madu) AS avg9day,
		MAX(crash_madu) as max9day
	FROM crash_madu
	WHERE report_date BETWEEN comp_bdate and comp_e1date
	GROUP BY product_version_id, signature_id
)
SELECT sum1day.signature_id,
	sum1day.product_version_id ,
	round (
		( sum1day.sum1day - agg9day.avg9day ) 
			/
		GREATEST ( agg9day.max9day - agg9day.avg9day, sum1day.mindivisor )
		, 2 )
	as explosive_1day
FROM sum1day 
	LEFT OUTER JOIN agg9day USING ( signature_id, product_version_id );
	
ANALYZE explosive_oneday;

-- create threeday temp table
CREATE TEMPORARY TABLE explosive_threeday
ON COMMIT DROP
AS
WITH adusum AS (
	SELECT adu_date, sum(adu_count) as adu_count,
		( mindiv_three * 1000000::numeric / sum(adu_count)) as mindivisor,
		product_version_id
	FROM product_adu
	WHERE adu_date BETWEEN comp_bdate and mes_edate
		AND adu_count > 0
	GROUP BY adu_date, product_version_id 
),
reportsum AS (
	SELECT report_date, sum(report_count) as report_count,
		product_version_id, signature_id
	FROM tcbs
	WHERE report_date BETWEEN comp_bdate and mes_edate
	GROUP BY report_date, product_version_id, signature_id
),
crash_madu AS (
	SELECT ( report_count * 1000000::numeric ) / adu_count AS crash_madu,
		reportsum.product_version_id, reportsum.signature_id, 
		report_date, mindivisor
	FROM adusum JOIN reportsum
		ON adu_date = report_date
		AND adusum.product_version_id = reportsum.product_version_id
),
avg3day AS ( 
	SELECT product_version_id, signature_id, avg(crash_madu) as avg3day,
		avg(mindivisor) as mindivisor
	FROM crash_madu
	WHERE report_date BETWEEN mes_b3date and mes_edate
	AND crash_madu > 10
	GROUP BY product_version_id, signature_id
),
agg7day AS (
	SELECT product_version_id, signature_id,
		AVG(crash_madu) AS avg7day,
		STDDEV(crash_madu) as sdv7day
	FROM crash_madu
	WHERE report_date BETWEEN comp_bdate and comp_e3date
	GROUP BY product_version_id, signature_id
)
SELECT avg3day.signature_id,
	avg3day.product_version_id ,
	round (
		( avg3day - avg7day ) 
			/
		GREATEST ( sdv7day - avg7day, avg3day.mindivisor )
		, 2 )
	as explosive_3day
FROM avg3day LEFT OUTER JOIN agg7day 
	USING ( signature_id, product_version_id );
	
ANALYZE explosive_threeday;
	
-- truncate explosiveness
DELETE FROM explosiveness;

-- merge the two tables and insert
INSERT INTO explosiveness (
	report_date, signature_id, product_version_id, 
	oneday, threeday )
SELECT updateday, signature_id, product_version_id, explosive_1day, explosive_3day
FROM explosive_oneday LEFT OUTER JOIN explosive_threeday
	USING ( signature_id, product_version_id )
ORDER BY product_version_id;
	
RETURN TRUE;
END; $$;


ALTER FUNCTION public.update_explosiveness(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1047 (class 1255 OID 538133)
-- Dependencies: 9 2923
-- Name: update_final_betas(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_final_betas(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN TRUE;
END; $$;


ALTER FUNCTION public.update_final_betas(updateday date) OWNER TO postgres;

--
-- TOC entry 1084 (class 1255 OID 737984)
-- Dependencies: 2923 9
-- Name: update_hang_report(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_hang_report(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET maintenance_work_mem TO '512MB'
    AS $$
BEGIN

-- check if reports_clean is complete
IF NOT reports_clean_done(updateday) THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Reports_clean has not been updated to the end of %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- check if we already have hang data
PERFORM 1 FROM daily_hangs
WHERE report_date = updateday LIMIT 1;
IF FOUND THEN
	RAISE EXCEPTION 'it appears that hang_report has already been run for %.  If you are backfilling, use backfill_hang_report instead.',updateday;
END IF;

-- insert data
-- note that we need to group on the plugin here and
-- take min() of all of the browser crash data.  this is a sloppy
-- approach but works because the only reason for more than one 
-- browser crash in a hang group is duplicate crash data
INSERT INTO daily_hangs ( uuid, plugin_uuid, report_date,
	product_version_id, browser_signature_id, plugin_signature_id,
	hang_id, flash_version_id, duplicates, url )
SELECT
    min(browser.uuid) ,
    plugin.uuid,
    updateday as report_date,
    min(browser.product_version_id),
    min(browser.signature_id),
    plugin.signature_id AS plugin_signature_id,
    plugin.hang_id,
    plugin.flash_version_id,
    nullif(array_agg(browser.duplicate_of) 
    	|| COALESCE(ARRAY[plugin.duplicate_of], '{}'),'{NULL}'),
    min(browser_info.url)
FROM reports_clean AS browser
    JOIN reports_clean AS plugin ON plugin.hang_id = browser.hang_id
    LEFT OUTER JOIN reports_user_info AS browser_info ON browser.uuid = browser_info.uuid
    JOIN signatures AS sig_browser
        ON sig_browser.signature_id = browser.signature_id
WHERE sig_browser.signature LIKE 'hang | %'
    AND browser.hang_id != ''
    AND browser.process_type = 'browser'
    AND plugin.process_type = 'plugin'
    AND utc_day_near(browser.date_processed, updateday)
    AND utc_day_is(plugin.date_processed, updateday)
    AND utc_day_is(browser_info.date_processed, updateday)
GROUP BY plugin.uuid, plugin.signature_id, plugin.hang_id, plugin.flash_version_id,
	plugin.duplicate_of;
    
ANALYZE daily_hangs;
RETURN TRUE;
END;$$;


ALTER FUNCTION public.update_hang_report(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1046 (class 1255 OID 737959)
-- Dependencies: 2923 9
-- Name: update_lookup_new_reports(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_lookup_new_reports(column_name text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare table_name text;
	insert_query text;
begin
	IF column_name LIKE '%s' THEN
		table_name := column_name || 'es';
	ELSE
		table_name := column_name || 's';
	END IF;
	
	insert_query := '
		insert into ' || table_name || ' ( ' || column_name || ', first_seen )
		select newrecords.* from ( 
			select ' || column_name || '::citext as col,
				min(date_processed) as first_report
			from new_reports
			group by col ) as newrecords
		left join ' || table_name || ' as lookuplist
			on newrecords.col = lookuplist.' || column_name || '
		where lookuplist.' || column_name || ' IS NULL;';
	
	execute insert_query;
	
	RETURN true;
end; $$;


ALTER FUNCTION public.update_lookup_new_reports(column_name text) OWNER TO postgres;

--
-- TOC entry 1093 (class 1255 OID 1142115)
-- Dependencies: 2923 9
-- Name: update_nightly_builds(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_nightly_builds(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET client_min_messages TO 'ERROR'
    AS $$
BEGIN
-- this function populates a daily matview
-- for **new_matview_description**
-- depends on the new reports_clean

-- check if we've been run
IF checkdata THEN
	PERFORM 1 FROM nightly_builds
	WHERE report_date = updateday
	LIMIT 1;
	IF FOUND THEN
		RAISE EXCEPTION 'nightly_builds has already been run for %.',updateday;
	END IF;
END IF;

-- check if reports_clean is complete
IF NOT reports_clean_done(updateday) THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Reports_clean has not been updated to the end of %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- now insert the new records
-- this should be some appropriate query, this simple group by
-- is just provided as an example
INSERT INTO nightly_builds (
	product_version_id, build_date, report_date,
	days_out, report_count )
SELECT product_version_id, 
	build_date(reports_clean.build) as build_date, 
	date_processed::date as report_date,
	date_processed::date 
		- build_date(reports_clean.build) as days_out,
	count(*)
FROM reports_clean
	join product_versions using (product_version_id)
	join product_version_builds using (product_version_id)
WHERE 
	reports_clean.build = product_version_builds.build_id
	and reports_clean.release_channel IN ( 'nightly', 'aurora' )
	and date_processed::date 
		- build_date(reports_clean.build) <= 14
	and tstz_between(date_processed, build_date, sunset_date)
	and utc_day_is(date_processed,updateday)
GROUP BY product_version_id, product_name, version_string,
	build_date(build), date_processed::date
ORDER BY product_version_id, build_date, days_out;

RETURN TRUE;
END; $$;


ALTER FUNCTION public.update_nightly_builds(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1073 (class 1255 OID 531789)
-- Dependencies: 2923 9
-- Name: update_os_versions(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_os_versions(updateday date) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET "TimeZone" TO 'UTC'
    AS $_$
BEGIN
-- function for daily batch update of os_version information
-- pulls new data out of reports
-- errors if no data found

create temporary table new_os
on commit drop as
select os_name, os_version
from reports
where date_processed >= updateday
	and date_processed <= ( updateday + 1 )
group by os_name, os_version;

PERFORM 1 FROM new_os LIMIT 1;
IF NOT FOUND THEN
	RAISE EXCEPTION 'No OS data found for date %',updateday;
END IF;

create temporary table os_versions_temp
on commit drop as
select os_name_matches.os_name,
	substring(os_version from $x$^(\d+)$x$)::int as major_version,
	substring(os_version from $x$^\d+\.(\d+)$x$)::int as minor_version
from new_os join os_name_matches
	ON new_os.os_name ILIKE match_string
where os_version ~ $x$^\d+$x$
	and substring(os_version from $x$^(\d+)$x$)::numeric < 1000
	and substring(os_version from $x$^\d+\.(\d+)$x$)::numeric < 1000;

insert into os_versions_temp
select os_name_matches.os_name,
	substring(os_version from $x$^(\d+)$x$)::int,
	0
from new_os join os_name_matches
	ON new_os.os_name ILIKE match_string
where os_version ~ $x$^\d+$x$
	and substring(os_version from $x$^(\d+)$x$)::numeric < 1000
	and ( substring(os_version from $x$^\d+\.(\d+)$x$)::numeric >= 1000
		or os_version !~ $x$^\d+\.(\d+)$x$ );

insert into os_versions_temp
select os_name_matches.os_name,
	0,
	0
from new_os join os_name_matches
	ON new_os.os_name ILIKE match_string
where os_version !~ $x$^\d+$x$
	or substring(os_version from $x$^(\d+)$x$)::numeric >= 1000
	or os_version is null;

insert into os_versions ( os_name, major_version, minor_version, os_version_string )
select os_name, major_version, minor_version,
	create_os_version_string( os_name, major_version, minor_version )
from (
select distinct os_name, major_version, minor_version
from os_versions_temp ) as os_rollup
left outer join os_versions
	USING ( os_name, major_version, minor_version )
where  os_versions.os_name is null;

RETURN true;
END; $_$;


ALTER FUNCTION public.update_os_versions(updateday date) OWNER TO postgres;

--
-- TOC entry 1076 (class 1255 OID 737961)
-- Dependencies: 9 2923
-- Name: update_os_versions_new_reports(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_os_versions_new_reports() RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $_$
BEGIN
-- function for updating list of oses and versions
-- intended to be called internally by update_reports_clean.

create temporary table new_os
on commit drop as
select os_name, os_version
from new_reports
group by os_name, os_version;

create temporary table os_versions_temp
on commit drop as
select os_name_matches.os_name,
	substring(os_version from $x$^(\d+)$x$)::int as major_version,
	substring(os_version from $x$^\d+\.(\d+)$x$)::int as minor_version
from new_os join os_name_matches
	ON new_os.os_name ILIKE match_string
where os_version ~ $x$^\d+$x$
	and substring(os_version from $x$^(\d+)$x$)::numeric < 1000
	and substring(os_version from $x$^\d+\.(\d+)$x$)::numeric < 1000;

insert into os_versions_temp
select os_name_matches.os_name,
	substring(os_version from $x$^(\d+)$x$)::int,
	0
from new_os join os_name_matches
	ON new_os.os_name ILIKE match_string
where os_version ~ $x$^\d+$x$
	and substring(os_version from $x$^(\d+)$x$)::numeric < 1000
	and ( substring(os_version from $x$^\d+\.(\d+)$x$)::numeric >= 1000
		or os_version !~ $x$^\d+\.(\d+)$x$ );

insert into os_versions_temp
select os_name_matches.os_name,
	0,
	0
from new_os join os_name_matches
	ON new_os.os_name ILIKE match_string
where os_version !~ $x$^\d+$x$
	or substring(os_version from $x$^(\d+)$x$)::numeric >= 1000
	or os_version is null;

insert into os_versions ( os_name, major_version, minor_version, os_version_string )
select os_name, major_version, minor_version,
	create_os_version_string( os_name, major_version, minor_version )
from (
select distinct os_name, major_version, minor_version
from os_versions_temp ) as os_rollup
left outer join os_versions
	USING ( os_name, major_version, minor_version )
where  os_versions.os_name is null;

drop table new_os;
drop table os_versions_temp;

RETURN true;
END; $_$;


ALTER FUNCTION public.update_os_versions_new_reports() OWNER TO postgres;

--
-- TOC entry 1086 (class 1255 OID 531781)
-- Dependencies: 2923 9
-- Name: update_product_versions(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_product_versions() RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET maintenance_work_mem TO '512MB'
    AS $$
BEGIN
-- daily batch update function for new products and versions
-- reads data from releases_raw, cleans it
-- and puts data corresponding to the new versions into
-- product_versions and related tables

-- is cumulative and can be run repeatedly without issues
-- now covers FennecAndroid and ESR releases
-- now only compares releases from the last 30 days

-- create temporary table, required because
-- all of the special cases

create temporary table releases_recent
on commit drop
as
select COALESCE ( specials.product_name, products.product_name )
		AS product_name,
	releases_raw.version,
	releases_raw.beta_number,
	releases_raw.build_id,
	releases_raw.build_type,
	releases_raw.platform,
	major_version_sort(version) >= major_version_sort(rapid_release_version) as is_rapid
from releases_raw
	JOIN products ON releases_raw.product_name = products.release_name
	LEFT OUTER JOIN special_product_platforms AS specials
		ON releases_raw.platform::citext = specials.platform
		AND releases_raw.product_name = specials.release_name
		AND releases_raw.repository = specials.repository
		AND releases_raw.build_type = specials.release_channel
		AND major_version_sort(version) >= major_version_sort(min_version)
where build_date(build_id) > ( current_date - 30 )
	AND version_matches_channel(releases_raw.version, releases_raw.build_type)
	AND releases_raw.repository NOT LIKE '%debug%';
	
--fix ESR versions

UPDATE releases_recent
SET build_type = 'ESR'
WHERE build_type ILIKE 'Release'
	AND version ILIKE '%esr';
	
-- now put it in product_versions

insert into product_versions (
    product_name,
    major_version,
    release_version,
    version_string,
    beta_number,
    version_sort,
    build_date,
    sunset_date,
    build_type)
select releases_recent.product_name,
	major_version(version),
	version,
	version_string(version, releases_recent.beta_number),
	releases_recent.beta_number,
	version_sort(version, releases_recent.beta_number),
	build_date(min(build_id)),
	sunset_date(min(build_id), releases_recent.build_type ),
	releases_recent.build_type::citext
from releases_recent
	left outer join product_versions ON
		( releases_recent.product_name = product_versions.product_name
			AND releases_recent.version = product_versions.release_version
			AND releases_recent.beta_number IS NOT DISTINCT FROM product_versions.beta_number )
where is_rapid
    AND product_versions.product_name IS NULL
group by releases_recent.product_name, version, 
	releases_recent.beta_number, 
	releases_recent.build_type::citext;

-- insert final betas as a copy of the release version

insert into product_versions (
    product_name,
    major_version,
    release_version,
    version_string,
    beta_number,
    version_sort,
    build_date,
    sunset_date,
    build_type)
select products.product_name,
    major_version(version),
    version,
    version || '(beta)',
    999,
    version_sort(version, 999),
    build_date(min(build_id)),
    sunset_date(min(build_id), 'beta' ),
    'beta'
from releases_recent
    join products ON releases_recent.product_name = products.release_name
    left outer join product_versions ON
        ( releases_recent.product_name = product_versions.product_name
            AND releases_recent.version = product_versions.release_version
            AND product_versions.beta_number = 999 )
where is_rapid
    AND releases_recent.product_name IS NULL
    AND releases_recent.build_type ILIKE 'release'
group by products.product_name, version;

-- add build ids

insert into product_version_builds
select distinct product_versions.product_version_id,
		releases_recent.build_id,
		releases_recent.platform
from releases_recent
	join product_versions
		ON releases_recent.product_name = product_versions.product_name
		AND releases_recent.version = product_versions.release_version
		AND releases_recent.build_type = product_versions.build_type
		AND ( releases_recent.beta_number IS NOT DISTINCT FROM product_versions.beta_number )
	left outer join product_version_builds ON
		product_versions.product_version_id = product_version_builds.product_version_id
		AND releases_recent.build_id = product_version_builds.build_id
		AND releases_recent.platform = product_version_builds.platform
where product_version_builds.product_version_id is null;

-- add build ids for final beta

insert into product_version_builds
select distinct product_versions.product_version_id,
		releases_recent.build_id,
		releases_recent.platform
from releases_recent
	join product_versions
		ON releases_recent.product_name = product_versions.product_name
		AND releases_recent.version = product_versions.release_version
		AND releases_recent.build_type ILIKE 'release'
		AND product_versions.beta_number = 999
	left outer join product_version_builds ON
		product_versions.product_version_id = product_version_builds.product_version_id
		AND releases_recent.build_id = product_version_builds.build_id
		AND releases_recent.platform = product_version_builds.platform
where product_version_builds.product_version_id is null;

return true;
end; $$;


ALTER FUNCTION public.update_product_versions() OWNER TO postgres;

--
-- TOC entry 1089 (class 1255 OID 1052944)
-- Dependencies: 2923 9
-- Name: update_rank_compare(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_rank_compare(updateday date DEFAULT NULL::date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET client_min_messages TO 'ERROR'
    AS $$
BEGIN
-- this function populates a daily matview
-- for rankings of signatures on TCBS
-- depends on the new reports_clean

-- run for yesterday if not set
updateday := COALESCE(updateday, ( CURRENT_DATE -1 ));

-- don't care if we've been run
-- since there's no historical data

-- check if reports_clean is complete
IF NOT reports_clean_done(updateday) THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Reports_clean has not been updated to the end of %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- obtain a lock on the matview so that we can TRUNCATE
IF NOT try_lock_table('rank_compare', 'ACCESS EXCLUSIVE') THEN
	RAISE EXCEPTION 'unable to lock the rank_compare table for update.';
END IF;

-- create temporary table with totals from reports_clean

CREATE TEMPORARY TABLE prod_sig_counts 
AS SELECT product_version_id, signature_id, count(*) as report_count
FROM reports_clean
WHERE utc_day_is(date_processed, updateday)
GROUP BY product_version_id, signature_id;

-- truncate rank_compare since we don't need the old data

TRUNCATE rank_compare CASCADE;

-- now insert the new records
INSERT INTO rank_compare (
	product_version_id, signature_id,
	rank_days,
	report_count,
	total_reports, 
	rank_report_count,
	percent_of_total)
SELECT product_version_id, signature_id,
	1, 
	report_count,
	total_count,
	count_rank,
	round(( report_count::numeric / total_count ),5)
FROM (
	SELECT product_version_id, signature_id,
		report_count,
		sum(report_count) over (partition by product_version_id) as total_count,
		dense_rank() over (partition by product_version_id 
							order by report_count desc) as count_rank
	FROM prod_sig_counts
) as initrank;

RETURN TRUE;
END; $$;


ALTER FUNCTION public.update_rank_compare(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1075 (class 1255 OID 737963)
-- Dependencies: 9 2923
-- Name: update_reports_clean(timestamp with time zone, interval, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_reports_clean(fromtime timestamp with time zone, fortime interval DEFAULT '01:00:00'::interval, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET maintenance_work_mem TO '512MB'
    SET client_min_messages TO 'ERROR'
    AS $_$
declare rc_part TEXT;
	rui_part TEXT;
	newfortime INTERVAL;
begin
-- this function creates a reports_clean fact table and all associated dimensions
-- intended to be run hourly for a target time three hours ago or so
-- eventually to be replaced by code for the processors to run

-- VERSION: 6

-- accepts a timestamptz, so be careful that the calling script is sending 
-- something appropriate

-- since we do allow dynamic timestamps, check if we split over a week
-- boundary.  if so, call self recursively for the first half of the period

IF ( week_begins_utc(fromtime) <> 
	week_begins_utc( fromtime + fortime - interval '1 second' ) ) THEN
	PERFORM update_reports_clean( fromtime, 
		( week_begins_utc( fromtime + fortime ) - fromtime ), checkdata );
	newfortime := ( fromtime + fortime ) - week_begins_utc( fromtime + fortime );
	fromtime := week_begins_utc( fromtime + fortime );
	fortime := newfortime;
END IF;

-- prevent calling for a period of more than one day

IF fortime > INTERVAL '1 day' THEN
	RAISE EXCEPTION 'you may not execute this function on more than one day of data';
END IF;

-- create a temporary table from the hour of reports you want to
-- process.  generally this will be from 3-4 hours ago to
-- avoid missing reports

-- RULE: replace NULL reason, address, flash_version, os_name with "Unknown"
-- RULE: replace NULL signature, url with ''
-- pre-cleaning: replace NULL product, version with ''
-- RULE: extract number of cores from cpu_info
-- RULE: convert all reference list TEXT values to CITEXT except Signature

create temporary table new_reports
on commit drop
as select uuid, 
	date_processed, 
	client_crash_date,
	uptime,
	install_age,
	build,
	COALESCE(signature, '')::text as signature,
	COALESCE(reason, 'Unknown')::citext as reason,
	COALESCE(address, 'Unknown')::citext as address,
	COALESCE(flash_version, 'Unknown')::citext as flash_version,
	COALESCE(product, '')::citext as product,
	COALESCE(version, '')::citext as version,
	COALESCE(os_name, 'Unknown')::citext as os_name,
	os_version::citext as os_version,
	coalesce(process_type, 'Browser') as process_type,
	COALESCE(url2domain(url),'') as domain,
	email, user_comments, url, app_notes,
	release_channel, hangid as hang_id,
	cpu_name as architecture,
	get_cores(cpu_info) as cores
from reports
where date_processed >= fromtime and date_processed < ( fromtime + fortime )
	and completed_datetime is not null;
	
-- check for no data

PERFORM 1 FROM new_reports
LIMIT 1;
IF NOT FOUND THEN
	IF checkdata THEN
		RAISE EXCEPTION 'no report data found for period %',fromtime;
	ELSE
		DROP TABLE new_reports;
		RETURN TRUE;
	END IF;
END IF;
	
create index new_reports_uuid on new_reports(uuid);
create index new_reports_signature on new_reports(signature);
create index new_reports_address on new_reports(address);
create index new_reports_domain on new_reports(domain);
create index new_reports_reason on new_reports(reason);
analyze new_reports;

-- trim reports_bad to 2 days of data
DELETE FROM reports_bad 
WHERE date_processed < ( now() - interval '2 days' );

-- delete any reports which were already processed
delete from new_reports
using reports_clean
where new_reports.uuid = reports_clean.uuid
and reports_clean.date_processed between ( fromtime - interval '1 day' )
and ( fromtime + fortime + interval '1 day' );

-- RULE: strip leading "0.0.0 Linux" from Linux version strings
UPDATE new_reports 
SET os_version = regexp_replace(os_version, $x$[0\.]+\s+Linux\s+$x$, '')
WHERE os_version LIKE '%0.0.0%'
	AND os_name ILIKE 'Linux%';

-- insert signatures into signature list
insert into signatures ( signature, first_report, first_build )
select newsigs.* from (
	select signature::citext as signature, 
		min(date_processed) as first_report, 
		min(build_numeric(build)) as first_build
	from new_reports
	group by signature::citext ) as newsigs
left join signatures
	on newsigs.signature = signatures.signature
where signatures.signature IS NULL;

-- insert oses into os list

PERFORM update_os_versions_new_reports();

-- insert reasons into reason list

PERFORM update_lookup_new_reports('reason');

-- insert addresses into address list

PERFORM update_lookup_new_reports('address');

-- insert flash_versions into flash version list

PERFORM update_lookup_new_reports('flash_version');

-- insert domains into the domain list

PERFORM update_lookup_new_reports('domain');

-- do not update reports_duplicates
-- this procedure assumes that it has already been run
-- later reports_duplicates will become a callable function from this function
-- maybe

-- create empty reports_clean_buffer
create temporary table reports_clean_buffer
(
uuid text not null primary key,
date_processed timestamptz not null,
client_crash_date timestamptz,
product_version_id int,
build numeric,
signature_id int,
install_age interval,
uptime interval,
reason_id int, 
address_id int,
os_name citext,
os_version_id int,
major_version int,
minor_version int,
hang_id text,
flash_version_id int,
process_type citext,
release_channel citext,
duplicate_of text,
domain_id int,
architecture citext,
cores int
) on commit drop ;

-- populate the new buffer with uuid, date_processed,
-- client_crash_date, build, install_time, uptime,
-- hang_id, duplicate_of, reason, address, flash_version,
-- release_channel

-- RULE: convert install_age, uptime to INTERVAL
-- RULE: convert reason, address, flash_version, URL domain to lookup list ID
-- RULE: add possible duplicate UUID link
-- RULE: convert release_channel to canonical release_channel based on
--	channel match list

INSERT INTO reports_clean_buffer
SELECT new_reports.uuid, 
	new_reports.date_processed,
	client_crash_date,
	0,
	build_numeric(build),
	signatures.signature_id,
	install_age * interval '1 second',
	uptime * interval '1 second',
	reasons.reason_id,
	addresses.address_id,
	NULL, NULL, 0, 0,
	hang_id,
	flash_versions.flash_version_id,
	process_type,
	release_channel_matches.release_channel,
	reports_duplicates.duplicate_of,
	domains.domain_id,
	architecture,
	cores
FROM new_reports
LEFT OUTER JOIN release_channel_matches ON new_reports.release_channel ILIKE release_channel_matches.match_string
LEFT OUTER JOIN signatures ON new_reports.signature = signatures.signature
LEFT OUTER JOIN reasons ON new_reports.reason = reasons.reason
LEFT OUTER JOIN addresses ON new_reports.address = addresses.address
LEFT OUTER JOIN flash_versions ON new_reports.flash_version = flash_versions.flash_version
LEFT OUTER JOIN reports_duplicates ON new_reports.uuid = reports_duplicates.uuid
	AND reports_duplicates.date_processed BETWEEN (fromtime - interval '1 day') AND (fromtime + interval '1 day' )
LEFT OUTER JOIN domains ON new_reports.domain = domains.domain
ORDER BY new_reports.uuid;

ANALYZE reports_clean_buffer;
	
-- populate product_version

	-- RULE: populate releases/aurora/nightlies based on matching product name
	-- and version with release_version
	
UPDATE reports_clean_buffer
SET product_version_id = product_versions.product_version_id
FROM product_versions, new_reports
WHERE reports_clean_buffer.uuid = new_reports.uuid
	AND new_reports.product = product_versions.product_name
	AND new_reports.version = product_versions.release_version
	AND reports_clean_buffer.release_channel = product_versions.build_type
	AND reports_clean_buffer.release_channel <> 'beta';

	-- RULE: populate betas based on matching product_name, version with
	-- release_version, and build number.
	
UPDATE reports_clean_buffer
SET product_version_id = product_versions.product_version_id
FROM product_versions JOIN product_version_builds USING (product_version_id), new_reports
WHERE reports_clean_buffer.uuid = new_reports.uuid
	AND new_reports.product = product_versions.product_name
	AND new_reports.version = product_versions.release_version
	AND reports_clean_buffer.release_channel = product_versions.build_type
	AND reports_clean_buffer.build = product_version_builds.build_id
	AND reports_clean_buffer.release_channel = 'beta';

-- populate os_name and os_version

-- RULE: set os_name based on name matching strings

UPDATE reports_clean_buffer SET os_name = os_name_matches.os_name
FROM new_reports, os_name_matches
WHERE reports_clean_buffer.uuid = new_reports.uuid
	AND new_reports.os_name ILIKE os_name_matches.match_string;
	
-- RULE: if os_name isn't recognized, set major and minor versions to 0.
UPDATE reports_clean_buffer SET os_name = 'Unknown',
	major_version = 0, minor_version = 0
WHERE os_name IS NULL OR os_name NOT IN ( SELECT os_name FROM os_names );

-- RULE: set minor_version based on parsing the os_version string
-- for a second decimal between 0 and 1000 if os_name is not Unknown
UPDATE reports_clean_buffer 
SET minor_version = substring(os_version from $x$^\d+\.(\d+)$x$)::int
FROM new_reports
WHERE new_reports.uuid = reports_clean_buffer.uuid
	and os_version ~ $x$^\d+$x$
	and substring(os_version from $x$^(\d+)$x$)::numeric < 1000
	and substring(os_version from $x$^\d+\.(\d+)$x$)::numeric < 1000
	and reports_clean_buffer.os_name <> 'Unknown';
	
-- RULE: set major_version based on parsing the os_vesion string
-- for a number between 0 and 1000, but there's no minor version
UPDATE reports_clean_buffer 
SET major_version = substring(os_version from $x$^(\d+)$x$)::int
FROM new_reports
WHERE new_reports.uuid = reports_clean_buffer.uuid
	AND os_version ~ $x$^\d+$x$
		and substring(os_version from $x$^(\d+)$x$)::numeric < 1000
		and reports_clean_buffer.major_version = 0
		and reports_clean_buffer.os_name <> 'Unknown';

UPDATE reports_clean_buffer
SET os_version_id = os_versions.os_version_id
FROM os_versions
WHERE reports_clean_buffer.os_name = os_versions.os_name
	AND reports_clean_buffer.major_version = os_versions.major_version
	AND reports_clean_buffer.minor_version = os_versions.minor_version;
	
-- copy to reports_bad and delete bad reports
-- RULE: currently we purge reports which have any of the following 
-- missing or invalid: product_version, release_channel, os_name

INSERT INTO reports_bad ( uuid, date_processed )
SELECT uuid, date_processed 
FROM reports_clean_buffer
WHERE product_version_id = 0
	OR release_channel IS NULL
	OR signature_id IS NULL;
	
DELETE FROM reports_clean_buffer
WHERE product_version_id = 0
	OR release_channel IS NULL
	OR signature_id IS NULL;
	
-- check if the right reports_clean partition exists, or create it

rc_part := reports_clean_weekly_partition(fromtime, 'reports_clean');

-- check if the right reports_user_info partition exists, or create it

rui_part := reports_clean_weekly_partition(fromtime, 'reports_user_info');

-- copy to reports_clean

EXECUTE 'INSERT INTO ' || rc_part || '
	( uuid, date_processed, client_crash_date, product_version_id, 
	  build, signature_id, install_age, uptime,
reason_id, address_id, os_name, os_version_id,
hang_id, flash_version_id, process_type, release_channel, 
duplicate_of, domain_id, architecture, cores )
SELECT uuid, date_processed, client_crash_date, product_version_id, 
	  build, signature_id, install_age, uptime,
reason_id, address_id, os_name, os_version_id,
hang_id, flash_version_id, process_type, release_channel, 
duplicate_of, domain_id, architecture, cores
FROM reports_clean_buffer;';

EXECUTE 'ANALYZE ' || rc_part;

-- copy to reports_user_info

EXECUTE 'INSERT INTO ' || rui_part || $$
	( uuid, date_processed, email, user_comments, url, app_notes )
SELECT new_reports.uuid, new_reports.date_processed,
		email, user_comments, url, app_notes
FROM new_reports JOIN reports_clean_buffer USING ( uuid )
WHERE email <> '' OR user_comments <> ''
	OR url <> '' OR app_notes <> '';$$;
	
EXECUTE 'ANALYZE ' || rui_part;

-- exit
DROP TABLE new_reports;
DROP TABLE reports_clean_buffer;
RETURN TRUE;

END;
$_$;


ALTER FUNCTION public.update_reports_clean(fromtime timestamp with time zone, fortime interval, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1058 (class 1255 OID 737965)
-- Dependencies: 9
-- Name: update_reports_clean_cron(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_reports_clean_cron(crontime timestamp with time zone) RETURNS boolean
    LANGUAGE sql
    AS $_$
SELECT update_reports_clean( date_trunc('hour', $1) - interval '1 hour' );
$_$;


ALTER FUNCTION public.update_reports_clean_cron(crontime timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 1087 (class 1255 OID 970001)
-- Dependencies: 2923 9
-- Name: update_reports_duplicates(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_reports_duplicates(start_time timestamp with time zone, end_time timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql
    SET work_mem TO '256MB'
    SET temp_buffers TO '128MB'
    AS $$
declare new_dups INT;
begin

-- create a temporary table with the new duplicates
-- for the hour
-- this query contains the duplicate-finding algorithm
-- so it will probably change frequently

create temporary table new_reports_duplicates
on commit drop
as
select follower.uuid as uuid,
	leader.uuid as duplicate_of,
	follower.date_processed
from
(
select uuid,
    install_age,
    uptime,
    client_crash_date,
    date_processed,
  first_value(uuid)
  over ( partition by
            product,
            version,
            build,
            signature,
            cpu_name,
            cpu_info,
            os_name,
            os_version,
            address,
            topmost_filenames,
            reason,
            app_notes,
            url
         order by
            client_crash_date,
            uuid
        ) as leader_uuid
   from reports
   where date_processed BETWEEN start_time AND end_time
 ) as follower
JOIN
  ( select uuid, install_age, uptime, client_crash_date
    FROM reports
    where date_processed BETWEEN start_time AND end_time ) as leader
  ON follower.leader_uuid = leader.uuid
WHERE ( same_time_fuzzy(leader.client_crash_date, follower.client_crash_date,
                  leader.uptime, follower.uptime)
		  OR follower.uptime < 60
  	  )
  AND
	same_time_fuzzy(leader.client_crash_date, follower.client_crash_date,
                  leader.install_age, follower.install_age)
  AND follower.uuid <> leader.uuid;

-- insert a copy of the leaders

insert into new_reports_duplicates
select uuid, uuid, date_processed
from reports
where uuid IN ( select duplicate_of
	from new_reports_duplicates )
	and date_processed BETWEEN start_time AND end_time;

analyze new_reports_duplicates;

select count(*) into new_dups from new_reports_duplicates;

-- insert new duplicates into permanent table

insert into reports_duplicates (uuid, duplicate_of, date_processed )
select new_reports_duplicates.*
from new_reports_duplicates
	left outer join reports_duplicates 
		ON new_reports_duplicates.uuid = reports_duplicates.uuid
		AND reports_duplicates.date_processed > ( start_time - INTERVAL '1 day' )
		AND reports_duplicates.date_processed < ( end_time + INTERVAL '1 day' )
where reports_duplicates.uuid IS NULL;

-- done return number of dups found and exit
DROP TABLE new_reports_duplicates;
RETURN new_dups;
end;$$;


ALTER FUNCTION public.update_reports_duplicates(start_time timestamp with time zone, end_time timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 1088 (class 1255 OID 656025)
-- Dependencies: 9 2923
-- Name: update_signatures(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_signatures(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    SET "TimeZone" TO 'UTC'
    AS $$
BEGIN

-- new function for updating signature information post-rapid-release
-- designed to be run once per UTC day.
-- running it repeatedly won't cause issues
-- combines NULL and empty signatures

-- create temporary table

create temporary table new_signatures
on commit drop as
select coalesce(signature,'') as signature, 
	product::citext as product, 
	version::citext as version, 
	build, NULL::INT as product_version_id,
	min(date_processed) as first_report
from reports
where date_processed >= updateday
	and date_processed <= (updateday + 1)
group by signature, product, version, build;

PERFORM 1 FROM new_signatures;
IF NOT FOUND THEN
	IF checkdata THEN
		RAISE EXCEPTION 'no signature data found in reports for date %',updateday;
	END IF;
END IF;

analyze new_signatures;

-- add product IDs for betas and matching builds
update new_signatures
set product_version_id = product_versions.product_version_id
from product_versions JOIN product_version_builds
	ON product_versions.product_version_id = product_version_builds.product_version_id
where product_versions.release_version = new_signatures.version
	and product_versions.product_name = new_signatures.product
	and product_version_builds.build_id::text = new_signatures.build;

-- add product IDs for builds that don't match
update new_signatures
set product_version_id = product_versions.product_version_id
from product_versions JOIN product_version_builds
	ON product_versions.product_version_id = product_version_builds.product_version_id
where product_versions.release_version = new_signatures.version
	and product_versions.product_name = new_signatures.product
	and product_versions.build_type IN ('release','nightly', 'aurora')
	and new_signatures.product_version_id IS NULL;

analyze new_signatures;

-- update signatures table

insert into signatures ( signature, first_report, first_build )
select new_signatures.signature, min(new_signatures.first_report),
	min(build_numeric(new_signatures.build))
from new_signatures
left outer join signatures
	on new_signatures.signature = signatures.signature
where signatures.signature is null
	and new_signatures.product_version_id is not null
group by new_signatures.signature;

-- update signature_products table

insert into signature_products ( signature_id, product_version_id, first_report )
select signatures.signature_id,
		new_signatures.product_version_id,
		min(new_signatures.first_report)
from new_signatures JOIN signatures
	ON new_signatures.signature = signatures.signature
	left outer join signature_products
		on signatures.signature_id = signature_products.signature_id
		and new_signatures.product_version_id = signature_products.product_version_id
where new_signatures.product_version_id is not null
	and signature_products.signature_id is null
group by signatures.signature_id,
		new_signatures.product_version_id;

-- recreate the rollup from scratch

DELETE FROM signature_products_rollup;

insert into signature_products_rollup ( signature_id, product_name, ver_count, version_list )
select
	signature_id, product_name, count(*) as ver_count,
		array_accum(version_string ORDER BY product_versions.version_sort)
from signature_products JOIN product_versions
	USING (product_version_id)
group by signature_id, product_name;

-- recreate signature_bugs from scratch

DELETE FROM signature_bugs_rollup;

INSERT INTO signature_bugs_rollup (signature_id, bug_count, bug_list)
SELECT signature_id, count(*), array_accum(bug_id)
FROM signatures JOIN bug_associations USING (signature)
GROUP BY signature_id;

return true;
end;
$$;


ALTER FUNCTION public.update_signatures(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1079 (class 1255 OID 907755)
-- Dependencies: 9 2923
-- Name: update_socorro_db_version(text, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_socorro_db_version(newversion text, backfilldate date DEFAULT NULL::date) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE rerun BOOLEAN;
BEGIN
	SELECT current_version = newversion
	INTO rerun
	FROM socorro_db_version;
	
	IF rerun THEN
		RAISE NOTICE 'This database is already set to version %.  If you have deliberately rerun the upgrade scripts, then this is as expected.  If not, then there is something wrong.',newversion;
	ELSE
		UPDATE socorro_db_version SET current_version = newversion;
	END IF;
	
	INSERT INTO socorro_db_version_history ( version, upgraded_on, backfill_to )
		VALUES ( newversion, now(), backfilldate );
	
	RETURN true;
END; $$;


ALTER FUNCTION public.update_socorro_db_version(newversion text, backfilldate date) OWNER TO postgres;

--
-- TOC entry 1099 (class 1255 OID 969739)
-- Dependencies: 2923 9
-- Name: update_tcbs(date, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION update_tcbs(updateday date, checkdata boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql
    SET work_mem TO '512MB'
    SET temp_buffers TO '512MB'
    AS $$
BEGIN
-- this procedure goes throught the daily TCBS update for the
-- new TCBS table
-- designed to be run only once for each day
-- this new version depends on reports_clean

-- check that it hasn't already been run

IF checkdata THEN
	PERFORM 1 FROM tcbs
	WHERE report_date = updateday LIMIT 1;
	IF FOUND THEN
		RAISE EXCEPTION 'TCBS has already been run for the day %.',updateday;
	END IF;
END IF;

-- check if reports_clean is complete
IF NOT reports_clean_done(updateday) THEN
	IF checkdata THEN
		RAISE EXCEPTION 'Reports_clean has not been updated to the end of %',updateday;
	ELSE
		RETURN TRUE;
	END IF;
END IF;

-- populate the matview

INSERT INTO tcbs (
	signature_id, report_date, product_version_id,
	process_type, release_channel,
	report_count, win_count, mac_count, lin_count, hang_count,
	startup_count
)
SELECT signature_id, updateday, product_version_id,
	process_type, release_channel,
	count(*),
	sum(case when os_name = 'Windows' THEN 1 else 0 END),
	sum(case when os_name = 'Mac OS X' THEN 1 else 0 END),
	sum(case when os_name = 'Linux' THEN 1 else 0 END),
    count(hang_id),
    sum(case when uptime < INTERVAL '1 minute' THEN 1 else 0 END)
FROM reports_clean
	JOIN product_versions USING (product_version_id)
	WHERE utc_day_is(date_processed, updateday)
		AND tstz_between(date_processed, build_date, sunset_date)
GROUP BY signature_id, updateday, product_version_id,
	process_type, release_channel;

ANALYZE tcbs;

-- tcbs_ranking removed until it's being used

-- done
RETURN TRUE;
END;
$$;


ALTER FUNCTION public.update_tcbs(updateday date, checkdata boolean) OWNER TO postgres;

--
-- TOC entry 1063 (class 1255 OID 722354)
-- Dependencies: 2076 9
-- Name: url2domain(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION url2domain(some_url text) RETURNS citext
    LANGUAGE sql IMMUTABLE
    AS $_$
select substring($1 FROM $x$^([\w:]+:/+(?:\w+\.)*\w+).*$x$)::citext
$_$;


ALTER FUNCTION public.url2domain(some_url text) OWNER TO postgres;

--
-- TOC entry 1057 (class 1255 OID 722355)
-- Dependencies: 9
-- Name: utc_day_is(timestamp with time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION utc_day_is(timestamp with time zone, timestamp without time zone) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
select $1 >= ( $2 AT TIME ZONE 'UTC' )
	AND $1 < ( ( $2 + INTERVAL '1 day' ) AT TIME ZONE 'UTC'  );
$_$;


ALTER FUNCTION public.utc_day_is(timestamp with time zone, timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 1065 (class 1255 OID 722356)
-- Dependencies: 9
-- Name: utc_day_near(timestamp with time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION utc_day_near(timestamp with time zone, timestamp without time zone) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
select $1 > ( $2 AT TIME ZONE 'UTC' - INTERVAL '1 day' )
AND $1 < ( $2 AT TIME ZONE 'UTC' + INTERVAL '2 days' )
$_$;


ALTER FUNCTION public.utc_day_near(timestamp with time zone, timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 1030 (class 1255 OID 740535)
-- Dependencies: 9 2076
-- Name: version_matches_channel(text, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_matches_channel(version text, channel citext) RETURNS boolean
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT CASE WHEN $1 ILIKE '%a1' AND $2 ILIKE 'nightly%'
	THEN TRUE
WHEN $1 ILIKE '%a2' AND $2 = 'aurora' 
	THEN TRUE
WHEN $1 ILIKE '%esr' AND $2 IN ( 'release', 'esr' )
	THEN TRUE
WHEN $1 NOT ILIKE '%a%' AND $1 NOT ILIKE '%esr' AND $2 IN ( 'beta', 'release' )
	THEN TRUE
ELSE FALSE END;
$_$;


ALTER FUNCTION public.version_matches_channel(version text, channel citext) OWNER TO postgres;

--
-- TOC entry 1096 (class 1255 OID 1125139)
-- Dependencies: 2923 2076 9 2076
-- Name: version_sort(text, integer, citext); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_sort(version text, beta_no integer DEFAULT 0, channel citext DEFAULT ''::citext) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE vne TEXT[];
	sortstring TEXT;
	dex INT;
BEGIN

	-- regexp the version number into tokens
	vne := regexp_matches( version, $x$^(\d+)\.(\d+)([a-zA-Z]*)(\d*)(?:\.(\d+))?(?:([a-zA-Z]+)(\d*))?.*$$x$ );
	
	-- bump betas after the 3rd digit back
	vne[3] := coalesce(nullif(vne[3],''),vne[6]);
	vne[4] := coalesce(nullif(vne[4],''),vne[7]);

	-- handle betal numbers
	IF beta_no > 0 THEN
		vne[3] := 'b';
		vne[4] := beta_no::TEXT;
	END IF;
	
	--handle final betas
	IF version LIKE '%(beta)%' THEN
		vne[3] := 'b';
		vne[4] := '99';
	END IF;
	
	--handle release channels
	CASE channel
		WHEN 'nightly' THEN
			vne[3] := 'a';
			vne[4] := '1';
		WHEN 'aurora' THEN
			vne[3] := 'a';
			vne[4] := '2';
		WHEN 'beta' THEN
			vne[3] := 'b';
			vne[4] := COALESCE(nullif(vne[4],''),99);
		WHEN 'release' THEN
			vne[3] := 'r';
			vne[4] := '0';
		WHEN 'ESR' THEN
			vne[3] := 'x';
			vne[4] := '0';
		ELSE
			NULL;
	END CASE;
	
	-- fix character otherwise
	IF vne[3] = 'esr' THEN
		vne[3] := 'x';
	ELSE
		vne[3] := COALESCE(nullif(vne[3],''),'r');
	END IF;
	
	--assemble string
	sortstring := version_sort_digit(vne[1]) 
		|| version_sort_digit(vne[2]) 
		|| version_sort_digit(vne[5]) 
		|| vne[3]
		|| version_sort_digit(vne[4]) ;
		
	RETURN sortstring;
END;$_$;


ALTER FUNCTION public.version_sort(version text, beta_no integer, channel citext) OWNER TO postgres;

--
-- TOC entry 1041 (class 1255 OID 531509)
-- Dependencies: 9
-- Name: version_sort_digit(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_sort_digit(digit text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
-- converts an individual part of a version number
-- into a three-digit sortable string
SELECT CASE WHEN $1 <> '' THEN
	to_char($1::INT,'FM000')
	ELSE '000' END;
$_$;


ALTER FUNCTION public.version_sort_digit(digit text) OWNER TO postgres;

--
-- TOC entry 1053 (class 1255 OID 880662)
-- Dependencies: 9 2923
-- Name: version_sort_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_sort_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	-- on insert or update, makes sure that the
	-- version_sort column is correct
	NEW.version_sort := old_version_sort(NEW.version);
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.version_sort_trigger() OWNER TO postgres;

--
-- TOC entry 1029 (class 1255 OID 267235)
-- Dependencies: 2923 9
-- Name: version_sort_update_trigger_after(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_sort_update_trigger_after() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
-- update sort keys
PERFORM product_version_sort_number(NEW.product);
RETURN NEW;
END; $$;


ALTER FUNCTION public.version_sort_update_trigger_after() OWNER TO postgres;

--
-- TOC entry 1028 (class 1255 OID 267234)
-- Dependencies: 2923 9
-- Name: version_sort_update_trigger_before(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_sort_update_trigger_before() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
-- updates productdims_version_sort
-- should be called only by a cascading update from productdims

-- update sort record
SELECT s1n1,s1s1,s1n2,s1s2,
s2n1,s2s1,s2n2,s2s2,
s3n1,s3s1,s3n2,s3s2,
ext
INTO 
NEW.sec1_num1,NEW.sec1_string1,NEW.sec1_num2,NEW.sec1_string2,
NEW.sec2_num1,NEW.sec2_string1,NEW.sec2_num2,NEW.sec2_string2,
NEW.sec3_num1,NEW.sec3_string1,NEW.sec3_num2,NEW.sec3_string2,
NEW.extra
FROM tokenize_version(NEW.version);

RETURN NEW;
END; $$;


ALTER FUNCTION public.version_sort_update_trigger_before() OWNER TO postgres;

--
-- TOC entry 1039 (class 1255 OID 531506)
-- Dependencies: 9
-- Name: version_string(text, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_string(version text, beta_number integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
-- converts a stripped version and a beta number
-- into a version string
SELECT CASE WHEN $2 <> 0 THEN
	$1 || 'b' || $2
ELSE
	$1
END;
$_$;


ALTER FUNCTION public.version_string(version text, beta_number integer) OWNER TO postgres;

--
-- TOC entry 1031 (class 1255 OID 656021)
-- Dependencies: 9
-- Name: version_string(text, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION version_string(version text, beta_number integer, channel text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
-- converts a stripped version and a beta number
-- into a version string
SELECT CASE WHEN $2 <> 0 THEN
	$1 || 'b' || $2
WHEN $3 ILIKE 'nightly' THEN
	$1 || 'a1'
WHEN $3 ILIKE 'aurora' THEN
	$1 || 'a2'
ELSE
	$1
END;
$_$;


ALTER FUNCTION public.version_string(version text, beta_number integer, channel text) OWNER TO postgres;

--
-- TOC entry 990 (class 1255 OID 54404)
-- Dependencies: 9 2923
-- Name: watch_report_processing(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION watch_report_processing(INOUT run_min integer, OUT report_count integer, OUT min_time interval, OUT max_time interval, OUT avg_time interval) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare reprec RECORD;
    cur_min interval;
    cur_max interval := '0 seconds';
    cur_tot interval := '0 seconds';
    cur_avg interval;
    cur_lag interval;
    cur_count int;
    last_report timestamp;
    end_time timestamptz;
    cur_time timestamptz;
    start_count int;
    start_time timestamptz;
    cur_loop INT := 0;
begin
  end_time := now() + run_min * interval '1 minute';
  start_time := now();

  select count(*) into start_count
  from reports where date_processed > ( start_time - interval '2 days' )
    and completed_datetime is not null;
  cur_time = clock_timestamp();

  while  cur_time < end_time loop

    select max(date_processed),
      count(*) - start_count
    into last_report, cur_count
    from reports where date_processed > ( start_time - interval '2 days' )
      and completed_datetime is not null;

    cur_loop := cur_loop + 1;
    cur_lag := cur_time - last_report;
    cur_tot := cur_tot + cur_lag;
    cur_min := LEAST(cur_min, cur_lag);
    cur_max := GREATEST(cur_max, cur_lag);
    cur_avg := cur_tot / cur_loop;

    RAISE INFO 'At: % Last Report: %',to_char(cur_time,'Mon DD HH24:MI:SS'),to_char(last_report,'Mon DD HH24:MI:SS');
    RAISE INFO 'Count: %   Lag: %  Min: %   Max: %   Avg: %', cur_count, to_char(cur_lag,'HH24:MI:SS'),to_char(cur_min, 'HH24:MI:SS'),to_char(cur_max, 'HH24:MI:SS'),to_char(cur_avg,'HH24:MI:SS');

    perform pg_sleep(10);
    cur_time := clock_timestamp();

  end loop;

  report_count := cur_count;
  min_time := cur_min;
  max_time := cur_max;
  avg_time := cur_avg;
  return;

  end;
$$;


ALTER FUNCTION public.watch_report_processing(INOUT run_min integer, OUT report_count integer, OUT min_time interval, OUT max_time interval, OUT avg_time interval) OWNER TO postgres;

--
-- TOC entry 1060 (class 1255 OID 969733)
-- Dependencies: 9
-- Name: week_begins_partition(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION week_begins_partition(partname text) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    SET "TimeZone" TO 'UTC'
    AS $_$
SELECT to_timestamp( substring($1 from $x$\d+$$x$), 'YYYYMMDD' );
$_$;


ALTER FUNCTION public.week_begins_partition(partname text) OWNER TO postgres;

--
-- TOC entry 1066 (class 1255 OID 969735)
-- Dependencies: 9
-- Name: week_begins_partition_string(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION week_begins_partition_string(partname text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET "TimeZone" TO 'UTC'
    AS $_$
SELECT to_char( week_begins_partition( $1 ), 'YYYY-MM-DD' ) || ' 00:00:00 UTC';
$_$;


ALTER FUNCTION public.week_begins_partition_string(partname text) OWNER TO postgres;

--
-- TOC entry 1062 (class 1255 OID 722352)
-- Dependencies: 9
-- Name: week_begins_utc(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION week_begins_utc(timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    SET "TimeZone" TO 'UTC'
    AS $_$
SELECT date_trunc('week', $1);
$_$;


ALTER FUNCTION public.week_begins_utc(timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 1064 (class 1255 OID 969734)
-- Dependencies: 9
-- Name: week_ends_partition(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION week_ends_partition(partname text) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    SET "TimeZone" TO 'UTC'
    AS $_$
SELECT to_timestamp( substring($1 from $x$\d+$$x$), 'YYYYMMDD' ) + INTERVAL '7 days';
$_$;


ALTER FUNCTION public.week_ends_partition(partname text) OWNER TO postgres;

--
-- TOC entry 1067 (class 1255 OID 969736)
-- Dependencies: 9
-- Name: week_ends_partition_string(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION week_ends_partition_string(partname text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET "TimeZone" TO 'UTC'
    AS $_$
SELECT to_char( week_ends_partition( $1 ), 'YYYY-MM-DD' ) || ' 00:00:00 UTC';
$_$;


ALTER FUNCTION public.week_ends_partition_string(partname text) OWNER TO postgres;

--
-- TOC entry 1051 (class 1255 OID 833218)
-- Dependencies: 9 2923
-- Name: weekly_report_partitions(integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION weekly_report_partitions(numweeks integer DEFAULT 2, targetdate timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
-- this function checks that we have partitions two weeks into
-- the future for each of the tables associated with
-- reports
-- designed to be called as a cronjob once a week
-- controlled by the data in the reports_partition_info table
DECLARE 
	thisweek DATE;
	dex INT := 1;
	weeknum INT := 0;
	tabinfo RECORD;
BEGIN
	targetdate := COALESCE(targetdate, now());
	thisweek := date_trunc('week', targetdate)::date;
	
	WHILE weeknum <= numweeks LOOP
		FOR tabinfo IN SELECT * FROM report_partition_info
			ORDER BY build_order LOOP
			
			PERFORM create_weekly_partition ( 
				tablename := tabinfo.table_name,
				theweek := thisweek,
				uniques := tabinfo.keys,
				indexes := tabinfo.indexes,
				fkeys := tabinfo.fkeys,
				tableowner := 'breakpad_rw'
			);

		END LOOP;
		weeknum := weeknum + 1;
		thisweek := thisweek + 7;
	END LOOP;

	RETURN TRUE;
	
END; $$;


ALTER FUNCTION public.weekly_report_partitions(numweeks integer, targetdate timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 2925 (class 1255 OID 48827)
-- Dependencies: 9
-- Name: array_accum(anyelement); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE array_accum(anyelement) (
    SFUNC = array_append,
    STYPE = anyarray,
    INITCOND = '{}'
);


ALTER AGGREGATE public.array_accum(anyelement) OWNER TO postgres;

--
-- TOC entry 2928 (class 1255 OID 737876)
-- Dependencies: 2076 9 1032
-- Name: content_count(citext, integer); Type: AGGREGATE; Schema: public; Owner: breakpad_rw
--

CREATE AGGREGATE content_count(citext, integer) (
    SFUNC = content_count_state,
    STYPE = integer,
    INITCOND = '0'
);


ALTER AGGREGATE public.content_count(citext, integer) OWNER TO breakpad_rw;

--
-- TOC entry 3640 (class 2617 OID 267093)
-- Dependencies: 9 999 2076 2076
-- Name: >; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR > (
    PROCEDURE = citext_gt,
    LEFTARG = citext,
    RIGHTARG = citext,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);


ALTER OPERATOR public.> (citext, citext) OWNER TO postgres;

--
-- TOC entry 2927 (class 1255 OID 267114)
-- Dependencies: 9 2076 2076 3640 1004
-- Name: max(citext); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE max(citext) (
    SFUNC = citext_larger,
    STYPE = citext,
    SORTOP = >
);


ALTER AGGREGATE public.max(citext) OWNER TO postgres;

--
-- TOC entry 3637 (class 2617 OID 267095)
-- Dependencies: 9 997 2076 2076
-- Name: <; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR < (
    PROCEDURE = citext_lt,
    LEFTARG = citext,
    RIGHTARG = citext,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);


ALTER OPERATOR public.< (citext, citext) OWNER TO postgres;

--
-- TOC entry 2926 (class 1255 OID 267113)
-- Dependencies: 2076 3637 1003 2076 9
-- Name: min(citext); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE min(citext) (
    SFUNC = citext_smaller,
    STYPE = citext,
    SORTOP = <
);


ALTER AGGREGATE public.min(citext) OWNER TO postgres;

--
-- TOC entry 2929 (class 1255 OID 523709)
-- Dependencies: 9 1040 2076
-- Name: plugin_count(citext, integer); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE plugin_count(citext, integer) (
    SFUNC = plugin_count_state,
    STYPE = integer,
    INITCOND = '0'
);


ALTER AGGREGATE public.plugin_count(citext, integer) OWNER TO postgres;

--
-- TOC entry 3643 (class 2617 OID 267119)
-- Dependencies: 9 2076 2076 1008
-- Name: !~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~ (
    PROCEDURE = texticregexne,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = ~,
    RESTRICT = icregexnesel,
    JOIN = icregexnejoinsel
);


ALTER OPERATOR public.!~ (citext, citext) OWNER TO postgres;

--
-- TOC entry 3651 (class 2617 OID 267131)
-- Dependencies: 2076 9 1012
-- Name: !~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~ (
    PROCEDURE = texticregexne,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = ~,
    RESTRICT = icregexnesel,
    JOIN = icregexnejoinsel
);


ALTER OPERATOR public.!~ (citext, text) OWNER TO postgres;

--
-- TOC entry 3644 (class 2617 OID 267121)
-- Dependencies: 1008 2076 9 2076
-- Name: !~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~* (
    PROCEDURE = texticregexne,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = ~*,
    RESTRICT = icregexnesel,
    JOIN = icregexnejoinsel
);


ALTER OPERATOR public.!~* (citext, citext) OWNER TO postgres;

--
-- TOC entry 3652 (class 2617 OID 267133)
-- Dependencies: 2076 1012 9
-- Name: !~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~* (
    PROCEDURE = texticregexne,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = ~*,
    RESTRICT = icregexnesel,
    JOIN = icregexnejoinsel
);


ALTER OPERATOR public.!~* (citext, text) OWNER TO postgres;

--
-- TOC entry 3647 (class 2617 OID 267123)
-- Dependencies: 2076 1006 2076 9
-- Name: !~~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~~ (
    PROCEDURE = texticnlike,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = ~~,
    RESTRICT = icnlikesel,
    JOIN = icnlikejoinsel
);


ALTER OPERATOR public.!~~ (citext, citext) OWNER TO postgres;

--
-- TOC entry 3655 (class 2617 OID 267135)
-- Dependencies: 2076 9 1010
-- Name: !~~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~~ (
    PROCEDURE = texticnlike,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = ~~,
    RESTRICT = icnlikesel,
    JOIN = icnlikejoinsel
);


ALTER OPERATOR public.!~~ (citext, text) OWNER TO postgres;

--
-- TOC entry 3648 (class 2617 OID 267125)
-- Dependencies: 2076 9 1006 2076
-- Name: !~~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~~* (
    PROCEDURE = texticnlike,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = ~~*,
    RESTRICT = icnlikesel,
    JOIN = icnlikejoinsel
);


ALTER OPERATOR public.!~~* (citext, citext) OWNER TO postgres;

--
-- TOC entry 3656 (class 2617 OID 267137)
-- Dependencies: 2076 9 1010
-- Name: !~~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR !~~* (
    PROCEDURE = texticnlike,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = ~~*,
    RESTRICT = icnlikesel,
    JOIN = icnlikejoinsel
);


ALTER OPERATOR public.!~~* (citext, text) OWNER TO postgres;

--
-- TOC entry 3638 (class 2617 OID 267096)
-- Dependencies: 2076 2076 998 9
-- Name: <=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <= (
    PROCEDURE = citext_le,
    LEFTARG = citext,
    RIGHTARG = citext,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel,
    JOIN = scalarltjoinsel
);


ALTER OPERATOR public.<= (citext, citext) OWNER TO postgres;

--
-- TOC entry 3636 (class 2617 OID 267091)
-- Dependencies: 9 2076 2076 996
-- Name: <>; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR <> (
    PROCEDURE = citext_ne,
    LEFTARG = citext,
    RIGHTARG = citext,
    COMMUTATOR = <>,
    NEGATOR = =,
    RESTRICT = neqsel,
    JOIN = neqjoinsel
);


ALTER OPERATOR public.<> (citext, citext) OWNER TO postgres;

--
-- TOC entry 3635 (class 2617 OID 267092)
-- Dependencies: 9 995 2076 2076
-- Name: =; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR = (
    PROCEDURE = citext_eq,
    LEFTARG = citext,
    RIGHTARG = citext,
    COMMUTATOR = =,
    NEGATOR = <>,
    MERGES,
    HASHES,
    RESTRICT = eqsel,
    JOIN = eqjoinsel
);


ALTER OPERATOR public.= (citext, citext) OWNER TO postgres;

--
-- TOC entry 3639 (class 2617 OID 267094)
-- Dependencies: 2076 2076 1000 9
-- Name: >=; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR >= (
    PROCEDURE = citext_ge,
    LEFTARG = citext,
    RIGHTARG = citext,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel,
    JOIN = scalargtjoinsel
);


ALTER OPERATOR public.>= (citext, citext) OWNER TO postgres;

--
-- TOC entry 3641 (class 2617 OID 267120)
-- Dependencies: 9 1007 2076 2076
-- Name: ~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~ (
    PROCEDURE = texticregexeq,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = !~,
    RESTRICT = icregexeqsel,
    JOIN = icregexeqjoinsel
);


ALTER OPERATOR public.~ (citext, citext) OWNER TO postgres;

--
-- TOC entry 3649 (class 2617 OID 267132)
-- Dependencies: 2076 1011 9
-- Name: ~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~ (
    PROCEDURE = texticregexeq,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = !~,
    RESTRICT = icregexeqsel,
    JOIN = icregexeqjoinsel
);


ALTER OPERATOR public.~ (citext, text) OWNER TO postgres;

--
-- TOC entry 3642 (class 2617 OID 267122)
-- Dependencies: 2076 9 2076 1007
-- Name: ~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~* (
    PROCEDURE = texticregexeq,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = !~*,
    RESTRICT = icregexeqsel,
    JOIN = icregexeqjoinsel
);


ALTER OPERATOR public.~* (citext, citext) OWNER TO postgres;

--
-- TOC entry 3650 (class 2617 OID 267134)
-- Dependencies: 2076 9 1011
-- Name: ~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~* (
    PROCEDURE = texticregexeq,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = !~*,
    RESTRICT = icregexeqsel,
    JOIN = icregexeqjoinsel
);


ALTER OPERATOR public.~* (citext, text) OWNER TO postgres;

--
-- TOC entry 3645 (class 2617 OID 267124)
-- Dependencies: 9 1005 2076 2076
-- Name: ~~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~~ (
    PROCEDURE = texticlike,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = !~~,
    RESTRICT = iclikesel,
    JOIN = iclikejoinsel
);


ALTER OPERATOR public.~~ (citext, citext) OWNER TO postgres;

--
-- TOC entry 3653 (class 2617 OID 267136)
-- Dependencies: 1009 2076 9
-- Name: ~~; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~~ (
    PROCEDURE = texticlike,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = !~~,
    RESTRICT = iclikesel,
    JOIN = iclikejoinsel
);


ALTER OPERATOR public.~~ (citext, text) OWNER TO postgres;

--
-- TOC entry 3646 (class 2617 OID 267126)
-- Dependencies: 1005 9 2076 2076
-- Name: ~~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~~* (
    PROCEDURE = texticlike,
    LEFTARG = citext,
    RIGHTARG = citext,
    NEGATOR = !~~*,
    RESTRICT = iclikesel,
    JOIN = iclikejoinsel
);


ALTER OPERATOR public.~~* (citext, citext) OWNER TO postgres;

--
-- TOC entry 3654 (class 2617 OID 267138)
-- Dependencies: 1009 9 2076
-- Name: ~~*; Type: OPERATOR; Schema: public; Owner: postgres
--

CREATE OPERATOR ~~* (
    PROCEDURE = texticlike,
    LEFTARG = citext,
    RIGHTARG = text,
    NEGATOR = !~~*,
    RESTRICT = iclikesel,
    JOIN = iclikejoinsel
);


ALTER OPERATOR public.~~* (citext, text) OWNER TO postgres;

--
-- TOC entry 3769 (class 2616 OID 267100)
-- Dependencies: 2076 9 3886
-- Name: citext_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS citext_ops
    DEFAULT FOR TYPE citext USING btree AS
    OPERATOR 1 <(citext,citext) ,
    OPERATOR 2 <=(citext,citext) ,
    OPERATOR 3 =(citext,citext) ,
    OPERATOR 4 >=(citext,citext) ,
    OPERATOR 5 >(citext,citext) ,
    FUNCTION 1 citext_cmp(citext,citext);


ALTER OPERATOR CLASS public.citext_ops USING btree OWNER TO postgres;

--
-- TOC entry 3770 (class 2616 OID 267108)
-- Dependencies: 2076 9 3887
-- Name: citext_ops; Type: OPERATOR CLASS; Schema: public; Owner: postgres
--

CREATE OPERATOR CLASS citext_ops
    DEFAULT FOR TYPE citext USING hash AS
    OPERATOR 1 =(citext,citext) ,
    FUNCTION 1 citext_hash(citext);


ALTER OPERATOR CLASS public.citext_ops USING hash OWNER TO postgres;

SET search_path = pg_catalog;

--
-- TOC entry 4120 (class 2605 OID 267083)
-- Dependencies: 993 993 2076
-- Name: CAST (boolean AS public.citext); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (boolean AS public.citext) WITH FUNCTION public.citext(boolean) AS ASSIGNMENT;


--
-- TOC entry 4246 (class 2605 OID 267082)
-- Dependencies: 992 2076 992
-- Name: CAST (character AS public.citext); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (character AS public.citext) WITH FUNCTION public.citext(character) AS ASSIGNMENT;


--
-- TOC entry 4313 (class 2605 OID 267079)
-- Dependencies: 2076
-- Name: CAST (public.citext AS character); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.citext AS character) WITHOUT FUNCTION AS ASSIGNMENT;


--
-- TOC entry 4312 (class 2605 OID 267077)
-- Dependencies: 2076
-- Name: CAST (public.citext AS text); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.citext AS text) WITHOUT FUNCTION AS IMPLICIT;


--
-- TOC entry 4314 (class 2605 OID 267078)
-- Dependencies: 2076
-- Name: CAST (public.citext AS character varying); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (public.citext AS character varying) WITHOUT FUNCTION AS IMPLICIT;


--
-- TOC entry 4239 (class 2605 OID 267084)
-- Dependencies: 994 2076 994
-- Name: CAST (inet AS public.citext); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (inet AS public.citext) WITH FUNCTION public.citext(inet) AS ASSIGNMENT;


--
-- TOC entry 4186 (class 2605 OID 267080)
-- Dependencies: 2076
-- Name: CAST (text AS public.citext); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (text AS public.citext) WITHOUT FUNCTION AS ASSIGNMENT;


--
-- TOC entry 4254 (class 2605 OID 267081)
-- Dependencies: 2076
-- Name: CAST (character varying AS public.citext); Type: CAST; Schema: pg_catalog; Owner: 
--

CREATE CAST (character varying AS public.citext) WITHOUT FUNCTION AS ASSIGNMENT;


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 789 (class 1259 OID 737905)
-- Dependencies: 2076 9
-- Name: addresses; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE addresses (
    address_id integer NOT NULL,
    address citext NOT NULL,
    first_seen timestamp with time zone
);


ALTER TABLE public.addresses OWNER TO breakpad_rw;

--
-- TOC entry 788 (class 1259 OID 737903)
-- Dependencies: 789 9
-- Name: addresses_address_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE addresses_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.addresses_address_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4666 (class 0 OID 0)
-- Dependencies: 788
-- Name: addresses_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE addresses_address_id_seq OWNED BY addresses.address_id;


--
-- TOC entry 558 (class 1259 OID 48828)
-- Dependencies: 4315 4316 9
-- Name: alexa_topsites; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE alexa_topsites (
    domain text NOT NULL,
    rank integer DEFAULT 10000,
    last_updated timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.alexa_topsites OWNER TO breakpad_rw;

--
-- TOC entry 559 (class 1259 OID 48836)
-- Dependencies: 4106 9
-- Name: bloat; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW bloat AS
    SELECT sml.schemaname, sml.tablename, (sml.reltuples)::bigint AS reltuples, (sml.relpages)::bigint AS relpages, sml.otta, round(CASE WHEN (sml.otta = (0)::double precision) THEN 0.0 ELSE ((sml.relpages)::numeric / (sml.otta)::numeric) END, 1) AS tbloat, (((sml.relpages)::bigint)::double precision - sml.otta) AS wastedpages, (sml.bs * ((((sml.relpages)::double precision - sml.otta))::bigint)::numeric) AS wastedbytes, pg_size_pretty((((sml.bs)::double precision * ((sml.relpages)::double precision - sml.otta)))::bigint) AS wastedsize, sml.iname, (sml.ituples)::bigint AS ituples, (sml.ipages)::bigint AS ipages, sml.iotta, round(CASE WHEN ((sml.iotta = (0)::double precision) OR (sml.ipages = 0)) THEN 0.0 ELSE ((sml.ipages)::numeric / (sml.iotta)::numeric) END, 1) AS ibloat, CASE WHEN ((sml.ipages)::double precision < sml.iotta) THEN (0)::double precision ELSE (((sml.ipages)::bigint)::double precision - sml.iotta) END AS wastedipages, CASE WHEN ((sml.ipages)::double precision < sml.iotta) THEN (0)::double precision ELSE ((sml.bs)::double precision * ((sml.ipages)::double precision - sml.iotta)) END AS wastedibytes, CASE WHEN ((sml.ipages)::double precision < sml.iotta) THEN pg_size_pretty((0)::bigint) ELSE pg_size_pretty((((sml.bs)::double precision * ((sml.ipages)::double precision - sml.iotta)))::bigint) END AS wastedisize FROM (SELECT rs.schemaname, rs.tablename, cc.reltuples, cc.relpages, rs.bs, ceil(((cc.reltuples * (((((rs.datahdr + (rs.ma)::numeric) - CASE WHEN ((rs.datahdr % (rs.ma)::numeric) = (0)::numeric) THEN (rs.ma)::numeric ELSE (rs.datahdr % (rs.ma)::numeric) END))::double precision + rs.nullhdr2) + (4)::double precision)) / ((rs.bs)::double precision - (20)::double precision))) AS otta, COALESCE(c2.relname, '?'::name) AS iname, COALESCE(c2.reltuples, (0)::real) AS ituples, COALESCE(c2.relpages, 0) AS ipages, COALESCE(ceil(((c2.reltuples * ((rs.datahdr - (12)::numeric))::double precision) / ((rs.bs)::double precision - (20)::double precision))), (0)::double precision) AS iotta FROM (((((SELECT foo.ma, foo.bs, foo.schemaname, foo.tablename, ((foo.datawidth + (((foo.hdr + foo.ma) - CASE WHEN ((foo.hdr % foo.ma) = 0) THEN foo.ma ELSE (foo.hdr % foo.ma) END))::double precision))::numeric AS datahdr, (foo.maxfracsum * (((foo.nullhdr + foo.ma) - CASE WHEN ((foo.nullhdr % (foo.ma)::bigint) = 0) THEN (foo.ma)::bigint ELSE (foo.nullhdr % (foo.ma)::bigint) END))::double precision) AS nullhdr2 FROM (SELECT s.schemaname, s.tablename, constants.hdr, constants.ma, constants.bs, sum((((1)::double precision - s.null_frac) * (s.avg_width)::double precision)) AS datawidth, max(s.null_frac) AS maxfracsum, (constants.hdr + (SELECT (1 + (count(*) / 8)) FROM pg_stats s2 WHERE (((s2.null_frac <> (0)::double precision) AND (s2.schemaname = s.schemaname)) AND (s2.tablename = s.tablename)))) AS nullhdr FROM pg_stats s, (SELECT (SELECT (current_setting('block_size'::text))::numeric AS current_setting) AS bs, CASE WHEN ("substring"(foo.v, 12, 3) = ANY (ARRAY['8.0'::text, '8.1'::text, '8.2'::text])) THEN 27 ELSE 23 END AS hdr, CASE WHEN (foo.v ~ 'mingw32'::text) THEN 8 ELSE 4 END AS ma FROM (SELECT version() AS v) foo) constants GROUP BY s.schemaname, s.tablename, constants.hdr, constants.ma, constants.bs) foo) rs JOIN pg_class cc ON ((cc.relname = rs.tablename))) JOIN pg_namespace nn ON (((cc.relnamespace = nn.oid) AND (nn.nspname = rs.schemaname)))) LEFT JOIN pg_index i ON ((i.indrelid = cc.oid))) LEFT JOIN pg_class c2 ON ((c2.oid = i.indexrelid)))) sml WHERE ((((sml.relpages)::double precision - sml.otta) > (0)::double precision) OR (((sml.ipages)::double precision - sml.iotta) > (10)::double precision)) ORDER BY (sml.bs * ((((sml.relpages)::double precision - sml.otta))::bigint)::numeric) DESC, CASE WHEN ((sml.ipages)::double precision < sml.iotta) THEN (0)::double precision ELSE ((sml.bs)::double precision * ((sml.ipages)::double precision - sml.iotta)) END DESC;


ALTER TABLE public.bloat OWNER TO postgres;

--
-- TOC entry 730 (class 1259 OID 531537)
-- Dependencies: 4348 4349 4350 2076 9 2076 2076 2372 2076
-- Name: product_versions; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_versions (
    product_version_id integer NOT NULL,
    product_name citext NOT NULL,
    major_version major_version NOT NULL,
    release_version citext NOT NULL,
    version_string citext NOT NULL,
    beta_number integer,
    version_sort text DEFAULT 0 NOT NULL,
    build_date date NOT NULL,
    sunset_date date NOT NULL,
    featured_version boolean DEFAULT false NOT NULL,
    build_type citext DEFAULT 'release'::citext NOT NULL
);


ALTER TABLE public.product_versions OWNER TO breakpad_rw;

--
-- TOC entry 602 (class 1259 OID 49604)
-- Dependencies: 730 9
-- Name: productdims_id_seq1; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE productdims_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.productdims_id_seq1 OWNER TO breakpad_rw;

--
-- TOC entry 4670 (class 0 OID 0)
-- Dependencies: 602
-- Name: productdims_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE productdims_id_seq1 OWNED BY product_versions.product_version_id;


--
-- TOC entry 560 (class 1259 OID 48841)
-- Dependencies: 4317 9 2076 2076 1387
-- Name: productdims; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE productdims (
    id integer DEFAULT nextval('productdims_id_seq1'::regclass) NOT NULL,
    product citext NOT NULL,
    version citext NOT NULL,
    branch text NOT NULL,
    release release_enum,
    sort_key integer,
    version_sort text
);


ALTER TABLE public.productdims OWNER TO breakpad_rw;

--
-- TOC entry 677 (class 1259 OID 267181)
-- Dependencies: 4110 9 2076 2076
-- Name: branches; Type: VIEW; Schema: public; Owner: breakpad_rw
--

CREATE VIEW branches AS
    SELECT productdims.product, productdims.version, productdims.branch FROM productdims;


ALTER TABLE public.branches OWNER TO breakpad_rw;

--
-- TOC entry 561 (class 1259 OID 48851)
-- Dependencies: 9
-- Name: bug_associations; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE bug_associations (
    signature text NOT NULL,
    bug_id integer NOT NULL
);


ALTER TABLE public.bug_associations OWNER TO breakpad_rw;

--
-- TOC entry 562 (class 1259 OID 48857)
-- Dependencies: 9
-- Name: bugs; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE bugs (
    id integer NOT NULL,
    status text,
    resolution text,
    short_desc text
);


ALTER TABLE public.bugs OWNER TO breakpad_rw;

--
-- TOC entry 563 (class 1259 OID 48863)
-- Dependencies: 4318 9 2076 2076 2076
-- Name: builds; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE builds (
    product citext,
    version citext,
    platform citext,
    buildid bigint,
    platform_changeset text,
    filename text,
    date timestamp without time zone DEFAULT now(),
    app_changeset_1 text,
    app_changeset_2 text
);


ALTER TABLE public.builds OWNER TO breakpad_rw;

--
-- TOC entry 902 (class 1259 OID 1101609)
-- Dependencies: 4378 9
-- Name: correlation_addons; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE correlation_addons (
    correlation_id integer NOT NULL,
    addon_key text NOT NULL,
    addon_version text NOT NULL,
    crash_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.correlation_addons OWNER TO breakpad_rw;

--
-- TOC entry 904 (class 1259 OID 1101637)
-- Dependencies: 4380 9 2076
-- Name: correlation_cores; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE correlation_cores (
    correlation_id integer NOT NULL,
    architecture citext NOT NULL,
    cores integer NOT NULL,
    crash_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.correlation_cores OWNER TO breakpad_rw;

--
-- TOC entry 903 (class 1259 OID 1101623)
-- Dependencies: 4379 9
-- Name: correlation_modules; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE correlation_modules (
    correlation_id integer NOT NULL,
    module_signature text NOT NULL,
    module_version text NOT NULL,
    crash_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.correlation_modules OWNER TO breakpad_rw;

--
-- TOC entry 901 (class 1259 OID 1101597)
-- Dependencies: 4377 9 2076
-- Name: correlations; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE correlations (
    correlation_id integer NOT NULL,
    product_version_id integer NOT NULL,
    os_name citext NOT NULL,
    reason_id integer NOT NULL,
    signature_id integer NOT NULL,
    crash_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.correlations OWNER TO breakpad_rw;

--
-- TOC entry 900 (class 1259 OID 1101595)
-- Dependencies: 901 9
-- Name: correlations_correlation_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE correlations_correlation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
    CYCLE;


ALTER TABLE public.correlations_correlation_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4681 (class 0 OID 0)
-- Dependencies: 900
-- Name: correlations_correlation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE correlations_correlation_id_seq OWNED BY correlations.correlation_id;


--
-- TOC entry 708 (class 1259 OID 431241)
-- Dependencies: 4343 9
-- Name: cronjobs; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE cronjobs (
    cronjob text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    frequency interval,
    lag interval,
    last_success timestamp with time zone,
    last_target_time timestamp with time zone,
    last_failure timestamp with time zone,
    failure_message text,
    description text
);


ALTER TABLE public.cronjobs OWNER TO breakpad_rw;

--
-- TOC entry 746 (class 1259 OID 531762)
-- Dependencies: 9 2076
-- Name: daily_crash_codes; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE daily_crash_codes (
    crash_code character(1) NOT NULL,
    crash_type citext
);


ALTER TABLE public.daily_crash_codes OWNER TO breakpad_rw;

--
-- TOC entry 564 (class 1259 OID 48870)
-- Dependencies: 4319 4320 9
-- Name: daily_crashes; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE daily_crashes (
    id integer NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    report_type character(1) DEFAULT 'C'::bpchar NOT NULL,
    productdims_id integer,
    os_short_name character(3),
    adu_day timestamp with time zone NOT NULL
);


ALTER TABLE public.daily_crashes OWNER TO breakpad_rw;

--
-- TOC entry 565 (class 1259 OID 48875)
-- Dependencies: 9 564
-- Name: daily_crashes_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE daily_crashes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.daily_crashes_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4685 (class 0 OID 0)
-- Dependencies: 565
-- Name: daily_crashes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE daily_crashes_id_seq OWNED BY daily_crashes.id;


--
-- TOC entry 796 (class 1259 OID 737969)
-- Dependencies: 9 2076
-- Name: daily_hangs; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE daily_hangs (
    uuid text NOT NULL,
    plugin_uuid text NOT NULL,
    report_date date,
    product_version_id integer NOT NULL,
    browser_signature_id integer NOT NULL,
    plugin_signature_id integer NOT NULL,
    hang_id text NOT NULL,
    flash_version_id integer,
    url citext,
    duplicates text[]
);


ALTER TABLE public.daily_hangs OWNER TO breakpad_rw;

--
-- TOC entry 791 (class 1259 OID 737918)
-- Dependencies: 2076 9
-- Name: domains; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE domains (
    domain_id integer NOT NULL,
    domain citext NOT NULL,
    first_seen timestamp with time zone
);


ALTER TABLE public.domains OWNER TO breakpad_rw;

--
-- TOC entry 790 (class 1259 OID 737916)
-- Dependencies: 791 9
-- Name: domains_domain_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE domains_domain_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.domains_domain_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4689 (class 0 OID 0)
-- Dependencies: 790
-- Name: domains_domain_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE domains_domain_id_seq OWNED BY domains.domain_id;


--
-- TOC entry 566 (class 1259 OID 48877)
-- Dependencies: 4322 4323 4325 9
-- Name: email_campaigns; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE email_campaigns (
    id integer NOT NULL,
    product text NOT NULL,
    versions text NOT NULL,
    signature text NOT NULL,
    subject text NOT NULL,
    body text NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    email_count integer DEFAULT 0,
    author text NOT NULL,
    date_created timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'stopped'::text NOT NULL
);


ALTER TABLE public.email_campaigns OWNER TO breakpad_rw;

--
-- TOC entry 567 (class 1259 OID 48885)
-- Dependencies: 4326 9
-- Name: email_campaigns_contacts; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE email_campaigns_contacts (
    email_campaigns_id integer,
    email_contacts_id integer,
    status text DEFAULT 'stopped'::text NOT NULL
);


ALTER TABLE public.email_campaigns_contacts OWNER TO breakpad_rw;

--
-- TOC entry 568 (class 1259 OID 48888)
-- Dependencies: 9 566
-- Name: email_campaigns_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE email_campaigns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.email_campaigns_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4692 (class 0 OID 0)
-- Dependencies: 568
-- Name: email_campaigns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE email_campaigns_id_seq OWNED BY email_campaigns.id;


--
-- TOC entry 569 (class 1259 OID 48890)
-- Dependencies: 4327 9
-- Name: email_contacts; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE email_contacts (
    id integer NOT NULL,
    email text NOT NULL,
    subscribe_token text NOT NULL,
    subscribe_status boolean DEFAULT true,
    ooid text,
    crash_date timestamp with time zone
);


ALTER TABLE public.email_contacts OWNER TO breakpad_rw;

--
-- TOC entry 570 (class 1259 OID 48897)
-- Dependencies: 569 9
-- Name: email_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE email_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.email_contacts_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4695 (class 0 OID 0)
-- Dependencies: 570
-- Name: email_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE email_contacts_id_seq OWNED BY email_contacts.id;


--
-- TOC entry 965 (class 1259 OID 1256293)
-- Dependencies: 9
-- Name: explosiveness; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE explosiveness (
    product_version_id integer NOT NULL,
    signature_id integer NOT NULL,
    report_date date NOT NULL,
    oneday numeric,
    threeday numeric
);


ALTER TABLE public.explosiveness OWNER TO breakpad_rw;

--
-- TOC entry 571 (class 1259 OID 48899)
-- Dependencies: 9
-- Name: extensions; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE extensions (
    report_id integer NOT NULL,
    date_processed timestamp with time zone,
    extension_key integer NOT NULL,
    extension_id text NOT NULL,
    extension_version text
);


ALTER TABLE public.extensions OWNER TO breakpad_rw;

--
-- TOC entry 787 (class 1259 OID 737892)
-- Dependencies: 9 2076
-- Name: flash_versions; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE flash_versions (
    flash_version_id integer NOT NULL,
    flash_version citext NOT NULL,
    first_seen timestamp with time zone
);


ALTER TABLE public.flash_versions OWNER TO breakpad_rw;

--
-- TOC entry 786 (class 1259 OID 737890)
-- Dependencies: 9 787
-- Name: flash_versions_flash_version_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE flash_versions_flash_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flash_versions_flash_version_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4700 (class 0 OID 0)
-- Dependencies: 786
-- Name: flash_versions_flash_version_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE flash_versions_flash_version_id_seq OWNED BY flash_versions.flash_version_id;


--
-- TOC entry 734 (class 1259 OID 531583)
-- Dependencies: 9
-- Name: signatures; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE signatures (
    signature_id integer NOT NULL,
    signature text,
    first_report timestamp with time zone,
    first_build numeric
);


ALTER TABLE public.signatures OWNER TO breakpad_rw;

--
-- TOC entry 797 (class 1259 OID 737986)
-- Dependencies: 4111 2076 9 2076 2076 2076
-- Name: hang_report; Type: VIEW; Schema: public; Owner: breakpad_rw
--

CREATE VIEW hang_report AS
    SELECT product_versions.product_name AS product, product_versions.version_string AS version, browser_signatures.signature AS browser_signature, plugin_signatures.signature AS plugin_signature, daily_hangs.hang_id AS browser_hangid, flash_versions.flash_version, daily_hangs.url, daily_hangs.uuid, daily_hangs.duplicates, daily_hangs.report_date AS report_day FROM ((((daily_hangs JOIN product_versions USING (product_version_id)) JOIN signatures browser_signatures ON ((daily_hangs.browser_signature_id = browser_signatures.signature_id))) JOIN signatures plugin_signatures ON ((daily_hangs.plugin_signature_id = plugin_signatures.signature_id))) LEFT JOIN flash_versions USING (flash_version_id));


ALTER TABLE public.hang_report OWNER TO breakpad_rw;

--
-- TOC entry 878 (class 1259 OID 975377)
-- Dependencies: 9
-- Name: high_load_temp; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE high_load_temp (
    now timestamp with time zone,
    datid oid,
    datname name,
    procpid integer,
    usesysid oid,
    usename name,
    application_name text,
    client_addr inet,
    client_port integer,
    backend_start timestamp with time zone,
    xact_start timestamp with time zone,
    query_start timestamp with time zone,
    waiting boolean,
    current_query text
);


ALTER TABLE public.high_load_temp OWNER TO postgres;

--
-- TOC entry 627 (class 1259 OID 52074)
-- Dependencies: 4340 9
-- Name: jobs; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE jobs (
    id integer NOT NULL,
    pathname character varying(1024) NOT NULL,
    uuid character varying(50) NOT NULL,
    owner integer,
    priority integer DEFAULT 0,
    queueddatetime timestamp with time zone,
    starteddatetime timestamp with time zone,
    completeddatetime timestamp with time zone,
    success boolean,
    message text
);


ALTER TABLE public.jobs OWNER TO breakpad_rw;

--
-- TOC entry 628 (class 1259 OID 52081)
-- Dependencies: 9 627
-- Name: jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
    CYCLE;


ALTER TABLE public.jobs_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4705 (class 0 OID 0)
-- Dependencies: 628
-- Name: jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE jobs_id_seq OWNED BY jobs.id;


--
-- TOC entry 632 (class 1259 OID 52123)
-- Dependencies: 4107 9
-- Name: jobs_in_queue; Type: VIEW; Schema: public; Owner: monitoring
--

CREATE VIEW jobs_in_queue AS
    SELECT count(*) AS count FROM jobs WHERE (jobs.completeddatetime IS NULL);


ALTER TABLE public.jobs_in_queue OWNER TO monitoring;

--
-- TOC entry 921 (class 1259 OID 1142108)
-- Dependencies: 4381 9
-- Name: nightly_builds; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE nightly_builds (
    product_version_id integer NOT NULL,
    build_date date NOT NULL,
    report_date date NOT NULL,
    days_out integer NOT NULL,
    report_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.nightly_builds OWNER TO breakpad_rw;

--
-- TOC entry 744 (class 1259 OID 531734)
-- Dependencies: 9 2076
-- Name: os_name_matches; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE os_name_matches (
    os_name citext NOT NULL,
    match_string text NOT NULL
);


ALTER TABLE public.os_name_matches OWNER TO breakpad_rw;

--
-- TOC entry 741 (class 1259 OID 531708)
-- Dependencies: 9 2076 2076
-- Name: os_names; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE os_names (
    os_name citext NOT NULL,
    os_short_name citext NOT NULL
);


ALTER TABLE public.os_names OWNER TO breakpad_rw;

--
-- TOC entry 743 (class 1259 OID 531718)
-- Dependencies: 2076 2076 9
-- Name: os_versions; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE os_versions (
    os_version_id integer NOT NULL,
    os_name citext NOT NULL,
    major_version integer NOT NULL,
    minor_version integer NOT NULL,
    os_version_string citext
);


ALTER TABLE public.os_versions OWNER TO breakpad_rw;

--
-- TOC entry 742 (class 1259 OID 531716)
-- Dependencies: 9 743
-- Name: os_versions_os_version_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE os_versions_os_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.os_versions_os_version_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4712 (class 0 OID 0)
-- Dependencies: 742
-- Name: os_versions_os_version_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE os_versions_os_version_id_seq OWNED BY os_versions.os_version_id;


--
-- TOC entry 583 (class 1259 OID 49315)
-- Dependencies: 9
-- Name: osdims; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE osdims (
    id integer NOT NULL,
    os_name character varying(100),
    os_version character varying(100)
);


ALTER TABLE public.osdims OWNER TO breakpad_rw;

--
-- TOC entry 584 (class 1259 OID 49318)
-- Dependencies: 583 9
-- Name: osdims_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE osdims_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.osdims_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4715 (class 0 OID 0)
-- Dependencies: 584
-- Name: osdims_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE osdims_id_seq OWNED BY osdims.id;


--
-- TOC entry 620 (class 1259 OID 49899)
-- Dependencies: 9
-- Name: top_crashes_by_signature; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE top_crashes_by_signature (
    id integer NOT NULL,
    count integer,
    uptime real,
    signature text,
    productdims_id integer,
    osdims_id integer,
    window_end timestamp without time zone,
    window_size interval,
    hang_count integer,
    plugin_count integer
);


ALTER TABLE public.top_crashes_by_signature OWNER TO breakpad_rw;

--
-- TOC entry 676 (class 1259 OID 267177)
-- Dependencies: 4109 9 2076
-- Name: performance_check_1; Type: VIEW; Schema: public; Owner: monitoring
--

CREATE VIEW performance_check_1 AS
    SELECT productdims.product, top_crashes_by_signature.signature, count(*) AS count FROM (top_crashes_by_signature JOIN productdims ON ((top_crashes_by_signature.productdims_id = productdims.id))) WHERE (top_crashes_by_signature.window_end > (now() - '1 day'::interval)) GROUP BY productdims.product, top_crashes_by_signature.signature ORDER BY count(*) LIMIT 50;


ALTER TABLE public.performance_check_1 OWNER TO monitoring;

--
-- TOC entry 657 (class 1259 OID 176630)
-- Dependencies: 4108 9
-- Name: pg_stat_statements; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW pg_stat_statements AS
    SELECT pg_stat_statements.userid, pg_stat_statements.dbid, pg_stat_statements.query, pg_stat_statements.calls, pg_stat_statements.total_time, pg_stat_statements.rows, pg_stat_statements.shared_blks_hit, pg_stat_statements.shared_blks_read, pg_stat_statements.shared_blks_written, pg_stat_statements.local_blks_hit, pg_stat_statements.local_blks_read, pg_stat_statements.local_blks_written, pg_stat_statements.temp_blks_read, pg_stat_statements.temp_blks_written FROM pg_stat_statements() pg_stat_statements(userid, dbid, query, calls, total_time, rows, shared_blks_hit, shared_blks_read, shared_blks_written, local_blks_hit, local_blks_read, local_blks_written, temp_blks_read, temp_blks_written);


ALTER TABLE public.pg_stat_statements OWNER TO postgres;

--
-- TOC entry 585 (class 1259 OID 49320)
-- Dependencies: 9
-- Name: plugins; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE plugins (
    id integer NOT NULL,
    filename text NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.plugins OWNER TO breakpad_rw;

--
-- TOC entry 586 (class 1259 OID 49326)
-- Dependencies: 9 585
-- Name: plugins_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE plugins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plugins_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4721 (class 0 OID 0)
-- Dependencies: 586
-- Name: plugins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE plugins_id_seq OWNED BY plugins.id;


--
-- TOC entry 587 (class 1259 OID 49328)
-- Dependencies: 9
-- Name: plugins_reports; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE plugins_reports (
    report_id integer NOT NULL,
    plugin_id integer NOT NULL,
    date_processed timestamp with time zone,
    version text NOT NULL
);


ALTER TABLE public.plugins_reports OWNER TO breakpad_rw;

--
-- TOC entry 852 (class 1259 OID 883139)
-- Dependencies: 9
-- Name: priority_jobs_1956; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_1956 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_1956 OWNER TO processor;

--
-- TOC entry 855 (class 1259 OID 902399)
-- Dependencies: 9
-- Name: priority_jobs_2034; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2034 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2034 OWNER TO processor;

--
-- TOC entry 910 (class 1259 OID 1115739)
-- Dependencies: 9
-- Name: priority_jobs_2276; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2276 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2276 OWNER TO processor;

--
-- TOC entry 955 (class 1259 OID 1256160)
-- Dependencies: 9
-- Name: priority_jobs_2510; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2510 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2510 OWNER TO processor;

--
-- TOC entry 956 (class 1259 OID 1256165)
-- Dependencies: 9
-- Name: priority_jobs_2511; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2511 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2511 OWNER TO processor;

--
-- TOC entry 957 (class 1259 OID 1256170)
-- Dependencies: 9
-- Name: priority_jobs_2512; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2512 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2512 OWNER TO processor;

--
-- TOC entry 958 (class 1259 OID 1256175)
-- Dependencies: 9
-- Name: priority_jobs_2513; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2513 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2513 OWNER TO processor;

--
-- TOC entry 959 (class 1259 OID 1256180)
-- Dependencies: 9
-- Name: priority_jobs_2514; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2514 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2514 OWNER TO processor;

--
-- TOC entry 960 (class 1259 OID 1256185)
-- Dependencies: 9
-- Name: priority_jobs_2515; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2515 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2515 OWNER TO processor;

--
-- TOC entry 961 (class 1259 OID 1256190)
-- Dependencies: 9
-- Name: priority_jobs_2516; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2516 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2516 OWNER TO processor;

--
-- TOC entry 962 (class 1259 OID 1256195)
-- Dependencies: 9
-- Name: priority_jobs_2517; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2517 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2517 OWNER TO processor;

--
-- TOC entry 963 (class 1259 OID 1256200)
-- Dependencies: 9
-- Name: priority_jobs_2518; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2518 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2518 OWNER TO processor;

--
-- TOC entry 964 (class 1259 OID 1256205)
-- Dependencies: 9
-- Name: priority_jobs_2519; Type: TABLE; Schema: public; Owner: processor; Tablespace: 
--

CREATE TABLE priority_jobs_2519 (
    uuid character varying(50) NOT NULL
);


ALTER TABLE public.priority_jobs_2519 OWNER TO processor;

--
-- TOC entry 629 (class 1259 OID 52083)
-- Dependencies: 9
-- Name: priorityjobs; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE priorityjobs (
    uuid character varying(255) NOT NULL
);


ALTER TABLE public.priorityjobs OWNER TO breakpad_rw;

--
-- TOC entry 630 (class 1259 OID 52086)
-- Dependencies: 9
-- Name: priorityjobs_log; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE priorityjobs_log (
    uuid character varying(255)
);


ALTER TABLE public.priorityjobs_log OWNER TO postgres;

--
-- TOC entry 631 (class 1259 OID 52089)
-- Dependencies: 9
-- Name: priorityjobs_logging_switch; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE priorityjobs_logging_switch (
    log_jobs boolean NOT NULL
);


ALTER TABLE public.priorityjobs_logging_switch OWNER TO postgres;

--
-- TOC entry 792 (class 1259 OID 737929)
-- Dependencies: 2076 9
-- Name: process_types; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE process_types (
    process_type citext NOT NULL
);


ALTER TABLE public.process_types OWNER TO breakpad_rw;

--
-- TOC entry 599 (class 1259 OID 49593)
-- Dependencies: 9
-- Name: processors; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE processors (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    startdatetime timestamp without time zone NOT NULL,
    lastseendatetime timestamp without time zone
);


ALTER TABLE public.processors OWNER TO breakpad_rw;

--
-- TOC entry 600 (class 1259 OID 49596)
-- Dependencies: 599 9
-- Name: processors_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE processors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.processors_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4742 (class 0 OID 0)
-- Dependencies: 600
-- Name: processors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE processors_id_seq OWNED BY processors.id;


--
-- TOC entry 745 (class 1259 OID 531747)
-- Dependencies: 4363 9 2076
-- Name: product_adu; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_adu (
    product_version_id integer NOT NULL,
    os_name citext NOT NULL,
    adu_date date NOT NULL,
    adu_count bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.product_adu OWNER TO breakpad_rw;

--
-- TOC entry 739 (class 1259 OID 531676)
-- Dependencies: 4361 9 2076 2076
-- Name: product_release_channels; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_release_channels (
    product_name citext NOT NULL,
    release_channel citext NOT NULL,
    throttle numeric DEFAULT 1.0 NOT NULL
);


ALTER TABLE public.product_release_channels OWNER TO breakpad_rw;

--
-- TOC entry 934 (class 1259 OID 1180797)
-- Dependencies: 4114 9 2076 2076
-- Name: product_crash_ratio; Type: VIEW; Schema: public; Owner: breakpad_rw
--

CREATE VIEW product_crash_ratio AS
    WITH crcounts AS (SELECT daily_crashes.productdims_id AS product_version_id, sum(daily_crashes.count) AS crashes, daily_crashes.adu_day AS report_date FROM daily_crashes WHERE ((daily_crashes.report_type = ANY (ARRAY['C'::bpchar, 'p'::bpchar, 'T'::bpchar, 'P'::bpchar])) AND (daily_crashes.count > 0)) GROUP BY daily_crashes.productdims_id, daily_crashes.adu_day), adusum AS (SELECT product_adu.product_version_id, product_adu.adu_date, sum(product_adu.adu_count) AS adu_count FROM product_adu GROUP BY product_adu.product_version_id, product_adu.adu_date) SELECT crcounts.product_version_id, product_versions.product_name, product_versions.version_string, adusum.adu_date, crcounts.crashes, adusum.adu_count, (product_release_channels.throttle)::numeric(5,2) AS throttle, (((crcounts.crashes)::numeric / product_release_channels.throttle))::integer AS adjusted_crashes, ((adusum.adu_count / (((crcounts.crashes)::numeric / product_release_channels.throttle) * (100)::numeric)))::numeric(12,3) AS crash_ratio FROM (((crcounts JOIN product_versions ON ((crcounts.product_version_id = product_versions.product_version_id))) JOIN adusum ON (((crcounts.report_date = adusum.adu_date) AND (crcounts.product_version_id = adusum.product_version_id)))) JOIN product_release_channels ON (((product_versions.product_name = product_release_channels.product_name) AND (product_versions.build_type = product_release_channels.release_channel))));


ALTER TABLE public.product_crash_ratio OWNER TO breakpad_rw;

--
-- TOC entry 601 (class 1259 OID 49598)
-- Dependencies: 4332 4333 4334 9
-- Name: product_visibility; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_visibility (
    productdims_id integer NOT NULL,
    start_date timestamp without time zone,
    end_date timestamp without time zone,
    ignore boolean DEFAULT false,
    featured boolean DEFAULT false,
    throttle numeric(5,2) DEFAULT 0.00
);


ALTER TABLE public.product_visibility OWNER TO breakpad_rw;

--
-- TOC entry 732 (class 1259 OID 531573)
-- Dependencies: 9 2076 1387
-- Name: release_build_type_map; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE release_build_type_map (
    release release_enum NOT NULL,
    build_type citext NOT NULL
);


ALTER TABLE public.release_build_type_map OWNER TO breakpad_rw;

--
-- TOC entry 844 (class 1259 OID 880669)
-- Dependencies: 4113 2076 2076 2076 9
-- Name: product_info; Type: VIEW; Schema: public; Owner: breakpad_rw
--

CREATE VIEW product_info AS
    SELECT product_versions.product_version_id, product_versions.product_name, product_versions.version_string, 'new'::text AS which_table, product_versions.build_date AS start_date, product_versions.sunset_date AS end_date, product_versions.featured_version AS is_featured, product_versions.build_type, ((product_release_channels.throttle * (100)::numeric))::numeric(5,2) AS throttle, product_versions.version_sort FROM (product_versions JOIN product_release_channels ON (((product_versions.product_name = product_release_channels.product_name) AND (product_versions.build_type = product_release_channels.release_channel)))) UNION ALL SELECT productdims.id AS product_version_id, productdims.product AS product_name, productdims.version AS version_string, 'old'::text AS which_table, product_visibility.start_date, product_visibility.end_date, product_visibility.featured AS is_featured, release_build_type_map.build_type, product_visibility.throttle, productdims.version_sort FROM (((productdims JOIN product_visibility ON ((productdims.id = product_visibility.productdims_id))) JOIN release_build_type_map ON ((productdims.release = release_build_type_map.release))) LEFT JOIN product_versions ON (((productdims.product = product_versions.product_name) AND ((productdims.version = product_versions.release_version) OR (productdims.version = product_versions.version_string))))) WHERE (product_versions.product_name IS NULL) ORDER BY 2, 3;


ALTER TABLE public.product_info OWNER TO breakpad_rw;

--
-- TOC entry 846 (class 1259 OID 880677)
-- Dependencies: 2446 2446 9
-- Name: product_info_changelog; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_info_changelog (
    product_version_id integer NOT NULL,
    user_name text NOT NULL,
    changed_on timestamp with time zone NOT NULL,
    oldrec product_info_change,
    newrec product_info_change
);


ALTER TABLE public.product_info_changelog OWNER TO breakpad_rw;

--
-- TOC entry 935 (class 1259 OID 1180802)
-- Dependencies: 4115 9 2076 2076 2076 2076
-- Name: product_os_crash_ratio; Type: VIEW; Schema: public; Owner: breakpad_rw
--

CREATE VIEW product_os_crash_ratio AS
    WITH crcounts AS (SELECT daily_crashes.productdims_id AS product_version_id, daily_crashes.os_short_name, sum(daily_crashes.count) AS crashes, daily_crashes.adu_day AS report_date FROM daily_crashes WHERE ((daily_crashes.report_type = ANY (ARRAY['C'::bpchar, 'p'::bpchar, 'T'::bpchar, 'P'::bpchar])) AND (daily_crashes.count > 0)) GROUP BY daily_crashes.productdims_id, daily_crashes.adu_day, daily_crashes.os_short_name) SELECT crcounts.product_version_id, product_versions.product_name, product_versions.version_string, os_names.os_short_name, os_names.os_name, product_adu.adu_date, crcounts.crashes, product_adu.adu_count, (product_release_channels.throttle)::numeric(5,2) AS throttle, (((crcounts.crashes)::numeric / product_release_channels.throttle))::integer AS adjusted_crashes, (((product_adu.adu_count)::numeric / (((crcounts.crashes)::numeric / product_release_channels.throttle) * (100)::numeric)))::numeric(12,3) AS crash_ratio FROM ((((crcounts JOIN product_versions ON ((crcounts.product_version_id = product_versions.product_version_id))) JOIN os_names ON (((crcounts.os_short_name)::citext = os_names.os_short_name))) JOIN product_adu ON ((((crcounts.report_date = product_adu.adu_date) AND (crcounts.product_version_id = product_adu.product_version_id)) AND (product_adu.os_name = os_names.os_name)))) JOIN product_release_channels ON (((product_versions.product_name = product_release_channels.product_name) AND (product_versions.build_type = product_release_channels.release_channel))));


ALTER TABLE public.product_os_crash_ratio OWNER TO breakpad_rw;

--
-- TOC entry 860 (class 1259 OID 907816)
-- Dependencies: 4375 9 2076 2372 2372
-- Name: product_productid_map; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_productid_map (
    product_name citext NOT NULL,
    productid text NOT NULL,
    rewrite boolean DEFAULT false NOT NULL,
    version_began major_version NOT NULL,
    version_ended major_version
);


ALTER TABLE public.product_productid_map OWNER TO breakpad_rw;

--
-- TOC entry 843 (class 1259 OID 880664)
-- Dependencies: 4112 2076 2076 9
-- Name: product_selector; Type: VIEW; Schema: public; Owner: breakpad_rw
--

CREATE VIEW product_selector AS
    SELECT product_versions.product_name, product_versions.version_string, 'new'::text AS which_table, product_versions.version_sort FROM product_versions WHERE (now() <= product_versions.sunset_date) UNION ALL SELECT productdims.product AS product_name, productdims.version AS version_string, 'old'::text AS which_table, productdims.version_sort FROM ((productdims JOIN product_visibility ON ((productdims.id = product_visibility.productdims_id))) LEFT JOIN product_versions ON (((productdims.product = product_versions.product_name) AND ((productdims.version = product_versions.release_version) OR (productdims.version = product_versions.version_string))))) WHERE ((product_versions.product_name IS NULL) AND ((now() >= product_visibility.start_date) AND (now() <= (product_visibility.end_date + '1 day'::interval)))) ORDER BY 1, 2;


ALTER TABLE public.product_selector OWNER TO breakpad_rw;

--
-- TOC entry 731 (class 1259 OID 531560)
-- Dependencies: 9
-- Name: product_version_builds; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE product_version_builds (
    product_version_id integer NOT NULL,
    build_id numeric NOT NULL,
    platform text NOT NULL
);


ALTER TABLE public.product_version_builds OWNER TO breakpad_rw;

--
-- TOC entry 678 (class 1259 OID 267216)
-- Dependencies: 2076 2076 9
-- Name: productdims_version_sort; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE productdims_version_sort (
    id integer NOT NULL,
    product citext NOT NULL,
    version citext NOT NULL,
    sec1_num1 integer,
    sec1_string1 text,
    sec1_num2 integer,
    sec1_string2 text,
    sec2_num1 integer,
    sec2_string1 text,
    sec2_num2 integer,
    sec2_string2 text,
    sec3_num1 integer,
    sec3_string1 text,
    sec3_num2 integer,
    sec3_string2 text,
    extra text
);


ALTER TABLE public.productdims_version_sort OWNER TO breakpad_rw;

--
-- TOC entry 728 (class 1259 OID 531519)
-- Dependencies: 4345 2372 2076 9 2076
-- Name: products; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE products (
    product_name citext NOT NULL,
    sort smallint DEFAULT 0 NOT NULL,
    rapid_release_version major_version,
    release_name citext NOT NULL
);


ALTER TABLE public.products OWNER TO breakpad_rw;

--
-- TOC entry 893 (class 1259 OID 1052934)
-- Dependencies: 9
-- Name: rank_compare; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE rank_compare (
    product_version_id integer NOT NULL,
    signature_id integer NOT NULL,
    rank_days integer NOT NULL,
    report_count integer,
    total_reports bigint,
    rank_report_count integer,
    percent_of_total numeric
);


ALTER TABLE public.rank_compare OWNER TO breakpad_rw;

--
-- TOC entry 603 (class 1259 OID 49606)
-- Dependencies: 9
-- Name: raw_adu; Type: TABLE; Schema: public; Owner: breakpad_metrics; Tablespace: 
--

CREATE TABLE raw_adu (
    adu_count integer,
    date date,
    product_name text,
    product_os_platform text,
    product_os_version text,
    product_version text,
    build text,
    build_channel text,
    product_guid text
);


ALTER TABLE public.raw_adu OWNER TO breakpad_metrics;

--
-- TOC entry 785 (class 1259 OID 737879)
-- Dependencies: 9 2076
-- Name: reasons; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE reasons (
    reason_id integer NOT NULL,
    reason citext NOT NULL,
    first_seen timestamp with time zone
);


ALTER TABLE public.reasons OWNER TO breakpad_rw;

--
-- TOC entry 784 (class 1259 OID 737877)
-- Dependencies: 9 785
-- Name: reasons_reason_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE reasons_reason_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reasons_reason_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4760 (class 0 OID 0)
-- Dependencies: 784
-- Name: reasons_reason_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE reasons_reason_id_seq OWNED BY reasons.reason_id;


--
-- TOC entry 740 (class 1259 OID 531695)
-- Dependencies: 2076 9
-- Name: release_channel_matches; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE release_channel_matches (
    release_channel citext NOT NULL,
    match_string text NOT NULL
);


ALTER TABLE public.release_channel_matches OWNER TO breakpad_rw;

--
-- TOC entry 729 (class 1259 OID 531528)
-- Dependencies: 4346 9 2076
-- Name: release_channels; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE release_channels (
    release_channel citext NOT NULL,
    sort smallint DEFAULT 0 NOT NULL
);


ALTER TABLE public.release_channels OWNER TO breakpad_rw;

--
-- TOC entry 727 (class 1259 OID 531004)
-- Dependencies: 4344 2076 9 2076 2076
-- Name: releases_raw; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE releases_raw (
    product_name citext NOT NULL,
    version text NOT NULL,
    platform text NOT NULL,
    build_id numeric NOT NULL,
    build_type citext NOT NULL,
    beta_number integer,
    repository citext DEFAULT 'mozilla-release'::citext NOT NULL
);


ALTER TABLE public.releases_raw OWNER TO breakpad_rw;

--
-- TOC entry 633 (class 1259 OID 54312)
-- Dependencies: 9
-- Name: replication_test; Type: TABLE; Schema: public; Owner: monitoring; Tablespace: 
--

CREATE TABLE replication_test (
    id smallint,
    test boolean
);


ALTER TABLE public.replication_test OWNER TO monitoring;

--
-- TOC entry 834 (class 1259 OID 833206)
-- Dependencies: 4370 4371 4372 4373 2076 9
-- Name: report_partition_info; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE report_partition_info (
    table_name citext NOT NULL,
    build_order integer DEFAULT 1 NOT NULL,
    keys text[] DEFAULT '{}'::text[] NOT NULL,
    indexes text[] DEFAULT '{}'::text[] NOT NULL,
    fkeys text[] DEFAULT '{}'::text[] NOT NULL
);


ALTER TABLE public.report_partition_info OWNER TO breakpad_rw;

--
-- TOC entry 604 (class 1259 OID 49612)
-- Dependencies: 9
-- Name: reports; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE reports (
    id integer NOT NULL,
    client_crash_date timestamp with time zone,
    date_processed timestamp with time zone,
    uuid character varying(50) NOT NULL,
    product character varying(30),
    version character varying(16),
    build character varying(30),
    signature character varying(255),
    url character varying(255),
    install_age integer,
    last_crash integer,
    uptime integer,
    cpu_name character varying(100),
    cpu_info character varying(100),
    reason character varying(255),
    address character varying(20),
    os_name character varying(100),
    os_version character varying(100),
    email character varying(100),
    user_id character varying(50),
    started_datetime timestamp with time zone,
    completed_datetime timestamp with time zone,
    success boolean,
    truncated boolean,
    processor_notes text,
    user_comments character varying(1024),
    app_notes character varying(1024),
    distributor character varying(20),
    distributor_version character varying(20),
    topmost_filenames text,
    addons_checked boolean,
    flash_version text,
    hangid text,
    process_type text,
    release_channel text,
    productid text
);


ALTER TABLE public.reports OWNER TO breakpad_rw;

--
-- TOC entry 795 (class 1259 OID 737953)
-- Dependencies: 9
-- Name: reports_bad; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE reports_bad (
    uuid text NOT NULL,
    date_processed timestamp with time zone NOT NULL
);


ALTER TABLE public.reports_bad OWNER TO breakpad_rw;

--
-- TOC entry 793 (class 1259 OID 737937)
-- Dependencies: 2076 2076 9 2076 2076
-- Name: reports_clean; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE reports_clean (
    uuid text NOT NULL,
    date_processed timestamp with time zone NOT NULL,
    client_crash_date timestamp with time zone,
    product_version_id integer,
    build numeric,
    signature_id integer NOT NULL,
    install_age interval,
    uptime interval,
    reason_id integer NOT NULL,
    address_id integer NOT NULL,
    os_name citext NOT NULL,
    os_version_id integer NOT NULL,
    hang_id text,
    flash_version_id integer NOT NULL,
    process_type citext NOT NULL,
    release_channel citext NOT NULL,
    duplicate_of text,
    domain_id integer NOT NULL,
    architecture citext,
    cores integer
);


ALTER TABLE public.reports_clean OWNER TO breakpad_rw;

--
-- TOC entry 672 (class 1259 OID 231523)
-- Dependencies: 9
-- Name: reports_duplicates; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE reports_duplicates (
    uuid text NOT NULL,
    duplicate_of text NOT NULL,
    date_processed timestamp with time zone NOT NULL
);


ALTER TABLE public.reports_duplicates OWNER TO breakpad_rw;

--
-- TOC entry 605 (class 1259 OID 49618)
-- Dependencies: 604 9
-- Name: reports_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reports_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4804 (class 0 OID 0)
-- Dependencies: 605
-- Name: reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE reports_id_seq OWNED BY reports.id;


--
-- TOC entry 794 (class 1259 OID 737945)
-- Dependencies: 2076 2076 2076 9
-- Name: reports_user_info; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE reports_user_info (
    uuid text NOT NULL,
    date_processed timestamp with time zone NOT NULL,
    user_comments citext,
    app_notes citext,
    email citext,
    url text
);


ALTER TABLE public.reports_user_info OWNER TO breakpad_rw;

--
-- TOC entry 617 (class 1259 OID 49879)
-- Dependencies: 9
-- Name: seq_reports_id; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE seq_reports_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.seq_reports_id OWNER TO breakpad_rw;

--
-- TOC entry 618 (class 1259 OID 49881)
-- Dependencies: 9
-- Name: server_status; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE server_status (
    id integer NOT NULL,
    date_recently_completed timestamp with time zone,
    date_oldest_job_queued timestamp with time zone,
    avg_process_sec real,
    avg_wait_sec real,
    waiting_job_count integer NOT NULL,
    processors_count integer NOT NULL,
    date_created timestamp with time zone NOT NULL
);


ALTER TABLE public.server_status OWNER TO breakpad_rw;

--
-- TOC entry 619 (class 1259 OID 49884)
-- Dependencies: 9 618
-- Name: server_status_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE server_status_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.server_status_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4813 (class 0 OID 0)
-- Dependencies: 619
-- Name: server_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE server_status_id_seq OWNED BY server_status.id;


--
-- TOC entry 660 (class 1259 OID 180439)
-- Dependencies: 4342 9
-- Name: sessions; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE sessions (
    session_id character varying(127) NOT NULL,
    last_activity integer NOT NULL,
    data text NOT NULL,
    CONSTRAINT last_activity_check CHECK ((last_activity >= 0))
);


ALTER TABLE public.sessions OWNER TO breakpad_rw;

--
-- TOC entry 738 (class 1259 OID 531661)
-- Dependencies: 4359 4360 9
-- Name: signature_bugs_rollup; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE signature_bugs_rollup (
    signature_id integer NOT NULL,
    bug_count integer DEFAULT 0 NOT NULL,
    bug_list integer[] DEFAULT '{}'::integer[] NOT NULL
);


ALTER TABLE public.signature_bugs_rollup OWNER TO breakpad_rw;

--
-- TOC entry 736 (class 1259 OID 531625)
-- Dependencies: 9
-- Name: signature_products; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE signature_products (
    signature_id integer NOT NULL,
    product_version_id integer NOT NULL,
    first_report timestamp with time zone
);


ALTER TABLE public.signature_products OWNER TO breakpad_rw;

--
-- TOC entry 737 (class 1259 OID 531641)
-- Dependencies: 4357 4358 9 2076
-- Name: signature_products_rollup; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE signature_products_rollup (
    signature_id integer NOT NULL,
    product_name citext NOT NULL,
    ver_count integer DEFAULT 0 NOT NULL,
    version_list text[] DEFAULT '{}'::text[] NOT NULL
);


ALTER TABLE public.signature_products_rollup OWNER TO breakpad_rw;

--
-- TOC entry 733 (class 1259 OID 531581)
-- Dependencies: 9 734
-- Name: signatures_signature_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE signatures_signature_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.signatures_signature_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4819 (class 0 OID 0)
-- Dependencies: 733
-- Name: signatures_signature_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE signatures_signature_id_seq OWNED BY signatures.signature_id;


--
-- TOC entry 858 (class 1259 OID 907738)
-- Dependencies: 9
-- Name: socorro_db_version; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE socorro_db_version (
    current_version text NOT NULL
);


ALTER TABLE public.socorro_db_version OWNER TO postgres;

--
-- TOC entry 859 (class 1259 OID 907746)
-- Dependencies: 4374 9
-- Name: socorro_db_version_history; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE socorro_db_version_history (
    version text NOT NULL,
    upgraded_on timestamp with time zone DEFAULT now() NOT NULL,
    backfill_to date
);


ALTER TABLE public.socorro_db_version_history OWNER TO postgres;

--
-- TOC entry 861 (class 1259 OID 907832)
-- Dependencies: 9 2372 2076 2076 2076 2076 2076
-- Name: special_product_platforms; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE special_product_platforms (
    platform citext NOT NULL,
    repository citext NOT NULL,
    release_channel citext NOT NULL,
    release_name citext NOT NULL,
    product_name citext NOT NULL,
    min_version major_version NOT NULL
);


ALTER TABLE public.special_product_platforms OWNER TO breakpad_rw;

--
-- TOC entry 735 (class 1259 OID 531594)
-- Dependencies: 4352 4353 4354 4355 4356 2076 2076 9
-- Name: tcbs; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE tcbs (
    signature_id integer NOT NULL,
    report_date date NOT NULL,
    product_version_id integer NOT NULL,
    process_type citext NOT NULL,
    release_channel citext NOT NULL,
    report_count integer DEFAULT 0 NOT NULL,
    win_count integer DEFAULT 0 NOT NULL,
    mac_count integer DEFAULT 0 NOT NULL,
    lin_count integer DEFAULT 0 NOT NULL,
    hang_count integer DEFAULT 0 NOT NULL,
    startup_count integer
);


ALTER TABLE public.tcbs OWNER TO breakpad_rw;

--
-- TOC entry 621 (class 1259 OID 49905)
-- Dependencies: 620 9
-- Name: top_crashes_by_signature_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE top_crashes_by_signature_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.top_crashes_by_signature_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4825 (class 0 OID 0)
-- Dependencies: 621
-- Name: top_crashes_by_signature_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE top_crashes_by_signature_id_seq OWNED BY top_crashes_by_signature.id;


--
-- TOC entry 622 (class 1259 OID 49907)
-- Dependencies: 9
-- Name: top_crashes_by_url; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE top_crashes_by_url (
    id integer NOT NULL,
    count integer,
    urldims_id integer,
    productdims_id integer,
    osdims_id integer,
    window_end timestamp without time zone,
    window_size interval
);


ALTER TABLE public.top_crashes_by_url OWNER TO breakpad_rw;

--
-- TOC entry 623 (class 1259 OID 49910)
-- Dependencies: 9 622
-- Name: top_crashes_by_url_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE top_crashes_by_url_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.top_crashes_by_url_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4828 (class 0 OID 0)
-- Dependencies: 623
-- Name: top_crashes_by_url_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE top_crashes_by_url_id_seq OWNED BY top_crashes_by_url.id;


--
-- TOC entry 624 (class 1259 OID 49912)
-- Dependencies: 9
-- Name: top_crashes_by_url_signature; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE top_crashes_by_url_signature (
    top_crashes_by_url_id integer NOT NULL,
    signature text NOT NULL,
    count integer
);


ALTER TABLE public.top_crashes_by_url_signature OWNER TO breakpad_rw;

--
-- TOC entry 928 (class 1259 OID 1159744)
-- Dependencies: 4383 4384 4385 4386 4387 4388 9 2076
-- Name: transform_rules; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE transform_rules (
    transform_rule_id integer NOT NULL,
    category citext NOT NULL,
    rule_order integer NOT NULL,
    predicate text DEFAULT ''::text NOT NULL,
    predicate_args text DEFAULT ''::text NOT NULL,
    predicate_kwargs text DEFAULT ''::text NOT NULL,
    action text DEFAULT ''::text NOT NULL,
    action_args text DEFAULT ''::text NOT NULL,
    action_kwargs text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.transform_rules OWNER TO breakpad_rw;

--
-- TOC entry 927 (class 1259 OID 1159742)
-- Dependencies: 9 928
-- Name: transform_rules_transform_rule_id_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE transform_rules_transform_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.transform_rules_transform_rule_id_seq OWNER TO breakpad_rw;

--
-- TOC entry 4832 (class 0 OID 0)
-- Dependencies: 927
-- Name: transform_rules_transform_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE transform_rules_transform_rule_id_seq OWNED BY transform_rules.transform_rule_id;


--
-- TOC entry 833 (class 1259 OID 833182)
-- Dependencies: 4369 9 2076
-- Name: uptime_levels; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE uptime_levels (
    uptime_level integer NOT NULL,
    uptime_string citext NOT NULL,
    min_uptime interval NOT NULL,
    max_uptime interval NOT NULL,
    CONSTRAINT period_check CHECK ((min_uptime < max_uptime))
);


ALTER TABLE public.uptime_levels OWNER TO breakpad_rw;

--
-- TOC entry 832 (class 1259 OID 833180)
-- Dependencies: 9 833
-- Name: uptime_levels_uptime_level_seq; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE uptime_levels_uptime_level_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.uptime_levels_uptime_level_seq OWNER TO breakpad_rw;

--
-- TOC entry 4834 (class 0 OID 0)
-- Dependencies: 832
-- Name: uptime_levels_uptime_level_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE uptime_levels_uptime_level_seq OWNED BY uptime_levels.uptime_level;


--
-- TOC entry 625 (class 1259 OID 49926)
-- Dependencies: 9
-- Name: urldims; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE urldims (
    id integer NOT NULL,
    domain text NOT NULL,
    url text NOT NULL
);


ALTER TABLE public.urldims OWNER TO breakpad_rw;

--
-- TOC entry 626 (class 1259 OID 49932)
-- Dependencies: 9 625
-- Name: urldims_id_seq1; Type: SEQUENCE; Schema: public; Owner: breakpad_rw
--

CREATE SEQUENCE urldims_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.urldims_id_seq1 OWNER TO breakpad_rw;

--
-- TOC entry 4836 (class 0 OID 0)
-- Dependencies: 626
-- Name: urldims_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: breakpad_rw
--

ALTER SEQUENCE urldims_id_seq1 OWNED BY urldims.id;


--
-- TOC entry 831 (class 1259 OID 833148)
-- Dependencies: 9 2076
-- Name: windows_versions; Type: TABLE; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE TABLE windows_versions (
    windows_version_name citext NOT NULL,
    major_version integer NOT NULL,
    minor_version integer NOT NULL
);


ALTER TABLE public.windows_versions OWNER TO breakpad_rw;

--
-- TOC entry 4366 (class 2604 OID 737908)
-- Dependencies: 788 789 789
-- Name: address_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY addresses ALTER COLUMN address_id SET DEFAULT nextval('addresses_address_id_seq'::regclass);


--
-- TOC entry 4376 (class 2604 OID 1101600)
-- Dependencies: 901 900 901
-- Name: correlation_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY correlations ALTER COLUMN correlation_id SET DEFAULT nextval('correlations_correlation_id_seq'::regclass);


--
-- TOC entry 4321 (class 2604 OID 49934)
-- Dependencies: 565 564
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY daily_crashes ALTER COLUMN id SET DEFAULT nextval('daily_crashes_id_seq'::regclass);


--
-- TOC entry 4367 (class 2604 OID 737921)
-- Dependencies: 790 791 791
-- Name: domain_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY domains ALTER COLUMN domain_id SET DEFAULT nextval('domains_domain_id_seq'::regclass);


--
-- TOC entry 4324 (class 2604 OID 49935)
-- Dependencies: 568 566
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY email_campaigns ALTER COLUMN id SET DEFAULT nextval('email_campaigns_id_seq'::regclass);


--
-- TOC entry 4328 (class 2604 OID 49936)
-- Dependencies: 570 569
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY email_contacts ALTER COLUMN id SET DEFAULT nextval('email_contacts_id_seq'::regclass);


--
-- TOC entry 4365 (class 2604 OID 737895)
-- Dependencies: 786 787 787
-- Name: flash_version_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY flash_versions ALTER COLUMN flash_version_id SET DEFAULT nextval('flash_versions_flash_version_id_seq'::regclass);


--
-- TOC entry 4341 (class 2604 OID 52092)
-- Dependencies: 628 627
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY jobs ALTER COLUMN id SET DEFAULT nextval('jobs_id_seq'::regclass);


--
-- TOC entry 4362 (class 2604 OID 531721)
-- Dependencies: 742 743 743
-- Name: os_version_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY os_versions ALTER COLUMN os_version_id SET DEFAULT nextval('os_versions_os_version_id_seq'::regclass);


--
-- TOC entry 4329 (class 2604 OID 49937)
-- Dependencies: 584 583
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY osdims ALTER COLUMN id SET DEFAULT nextval('osdims_id_seq'::regclass);


--
-- TOC entry 4330 (class 2604 OID 49938)
-- Dependencies: 586 585
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY plugins ALTER COLUMN id SET DEFAULT nextval('plugins_id_seq'::regclass);


--
-- TOC entry 4331 (class 2604 OID 49939)
-- Dependencies: 600 599
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY processors ALTER COLUMN id SET DEFAULT nextval('processors_id_seq'::regclass);


--
-- TOC entry 4347 (class 2604 OID 531540)
-- Dependencies: 730 602 730
-- Name: product_version_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_versions ALTER COLUMN product_version_id SET DEFAULT nextval('productdims_id_seq1'::regclass);


--
-- TOC entry 4364 (class 2604 OID 737882)
-- Dependencies: 784 785 785
-- Name: reason_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY reasons ALTER COLUMN reason_id SET DEFAULT nextval('reasons_reason_id_seq'::regclass);


--
-- TOC entry 4335 (class 2604 OID 49941)
-- Dependencies: 605 604
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY reports ALTER COLUMN id SET DEFAULT nextval('reports_id_seq'::regclass);


--
-- TOC entry 4336 (class 2604 OID 49979)
-- Dependencies: 619 618
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY server_status ALTER COLUMN id SET DEFAULT nextval('server_status_id_seq'::regclass);


--
-- TOC entry 4351 (class 2604 OID 531586)
-- Dependencies: 733 734 734
-- Name: signature_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY signatures ALTER COLUMN signature_id SET DEFAULT nextval('signatures_signature_id_seq'::regclass);


--
-- TOC entry 4337 (class 2604 OID 49980)
-- Dependencies: 621 620
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY top_crashes_by_signature ALTER COLUMN id SET DEFAULT nextval('top_crashes_by_signature_id_seq'::regclass);


--
-- TOC entry 4338 (class 2604 OID 49981)
-- Dependencies: 623 622
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY top_crashes_by_url ALTER COLUMN id SET DEFAULT nextval('top_crashes_by_url_id_seq'::regclass);


--
-- TOC entry 4382 (class 2604 OID 1159747)
-- Dependencies: 927 928 928
-- Name: transform_rule_id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY transform_rules ALTER COLUMN transform_rule_id SET DEFAULT nextval('transform_rules_transform_rule_id_seq'::regclass);


--
-- TOC entry 4368 (class 2604 OID 833185)
-- Dependencies: 833 832 833
-- Name: uptime_level; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY uptime_levels ALTER COLUMN uptime_level SET DEFAULT nextval('uptime_levels_uptime_level_seq'::regclass);


--
-- TOC entry 4339 (class 2604 OID 49983)
-- Dependencies: 626 625
-- Name: id; Type: DEFAULT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY urldims ALTER COLUMN id SET DEFAULT nextval('urldims_id_seq1'::regclass);


--
-- TOC entry 4533 (class 2606 OID 737915)
-- Dependencies: 789 789
-- Name: addresses_address_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY addresses
    ADD CONSTRAINT addresses_address_key UNIQUE (address);


--
-- TOC entry 4535 (class 2606 OID 737913)
-- Dependencies: 789 789
-- Name: addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (address_id);


--
-- TOC entry 4390 (class 2606 OID 50434)
-- Dependencies: 558 558
-- Name: alexa_topsites_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY alexa_topsites
    ADD CONSTRAINT alexa_topsites_pkey PRIMARY KEY (domain);


--
-- TOC entry 4396 (class 2606 OID 50436)
-- Dependencies: 561 561 561
-- Name: bug_associations_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY bug_associations
    ADD CONSTRAINT bug_associations_pkey PRIMARY KEY (signature, bug_id);


--
-- TOC entry 4399 (class 2606 OID 50439)
-- Dependencies: 562 562
-- Name: bugs_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY bugs
    ADD CONSTRAINT bugs_pkey PRIMARY KEY (id);


--
-- TOC entry 4588 (class 2606 OID 1101617)
-- Dependencies: 902 902 902 902
-- Name: correlation_addons_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY correlation_addons
    ADD CONSTRAINT correlation_addons_key UNIQUE (correlation_id, addon_key, addon_version);


--
-- TOC entry 4592 (class 2606 OID 1101645)
-- Dependencies: 904 904 904 904
-- Name: correlation_cores_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY correlation_cores
    ADD CONSTRAINT correlation_cores_key UNIQUE (correlation_id, architecture, cores);


--
-- TOC entry 4590 (class 2606 OID 1101631)
-- Dependencies: 903 903 903 903
-- Name: correlation_modules_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY correlation_modules
    ADD CONSTRAINT correlation_modules_key UNIQUE (correlation_id, module_signature, module_version);


--
-- TOC entry 4584 (class 2606 OID 1101608)
-- Dependencies: 901 901 901 901 901
-- Name: correlations_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY correlations
    ADD CONSTRAINT correlations_key UNIQUE (product_version_id, os_name, reason_id, signature_id);


--
-- TOC entry 4586 (class 2606 OID 1101606)
-- Dependencies: 901 901
-- Name: correlations_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY correlations
    ADD CONSTRAINT correlations_pkey PRIMARY KEY (correlation_id);


--
-- TOC entry 4472 (class 2606 OID 431249)
-- Dependencies: 708 708
-- Name: cronjobs_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY cronjobs
    ADD CONSTRAINT cronjobs_pkey PRIMARY KEY (cronjob);


--
-- TOC entry 4523 (class 2606 OID 531769)
-- Dependencies: 746 746
-- Name: daily_crash_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY daily_crash_codes
    ADD CONSTRAINT daily_crash_codes_pkey PRIMARY KEY (crash_code);


--
-- TOC entry 4402 (class 2606 OID 50467)
-- Dependencies: 564 564
-- Name: daily_crashes_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY daily_crashes
    ADD CONSTRAINT daily_crashes_pkey PRIMARY KEY (id);


--
-- TOC entry 4550 (class 2606 OID 737976)
-- Dependencies: 796 796
-- Name: daily_hangs_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY daily_hangs
    ADD CONSTRAINT daily_hangs_pkey PRIMARY KEY (plugin_uuid);


--
-- TOC entry 4404 (class 2606 OID 532996)
-- Dependencies: 564 564 564 564 564
-- Name: day_product_os_report_type_unique; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY daily_crashes
    ADD CONSTRAINT day_product_os_report_type_unique UNIQUE (adu_day, productdims_id, os_short_name, report_type);


--
-- TOC entry 4537 (class 2606 OID 737928)
-- Dependencies: 791 791
-- Name: domains_domain_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY domains
    ADD CONSTRAINT domains_domain_key UNIQUE (domain);


--
-- TOC entry 4539 (class 2606 OID 737926)
-- Dependencies: 791 791
-- Name: domains_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY domains
    ADD CONSTRAINT domains_pkey PRIMARY KEY (domain_id);


--
-- TOC entry 4409 (class 2606 OID 50432)
-- Dependencies: 567 567 567
-- Name: email_campaigns_contacts_mapping_unique; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY email_campaigns_contacts
    ADD CONSTRAINT email_campaigns_contacts_mapping_unique UNIQUE (email_campaigns_id, email_contacts_id);


--
-- TOC entry 4406 (class 2606 OID 50446)
-- Dependencies: 566 566
-- Name: email_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY email_campaigns
    ADD CONSTRAINT email_campaigns_pkey PRIMARY KEY (id);


--
-- TOC entry 4411 (class 2606 OID 50454)
-- Dependencies: 569 569
-- Name: email_contacts_email_unique; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY email_contacts
    ADD CONSTRAINT email_contacts_email_unique UNIQUE (email);


--
-- TOC entry 4413 (class 2606 OID 50456)
-- Dependencies: 569 569
-- Name: email_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY email_contacts
    ADD CONSTRAINT email_contacts_pkey PRIMARY KEY (id);


--
-- TOC entry 4415 (class 2606 OID 50458)
-- Dependencies: 569 569
-- Name: email_contacts_token_unique; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY email_contacts
    ADD CONSTRAINT email_contacts_token_unique UNIQUE (subscribe_token);


--
-- TOC entry 4623 (class 2606 OID 1256300)
-- Dependencies: 965 965 965 965
-- Name: explosiveness_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY explosiveness
    ADD CONSTRAINT explosiveness_key PRIMARY KEY (product_version_id, signature_id, report_date);


--
-- TOC entry 4420 (class 2606 OID 50723)
-- Dependencies: 585 585 585
-- Name: filename_name_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY plugins
    ADD CONSTRAINT filename_name_key UNIQUE (filename, name);


--
-- TOC entry 4529 (class 2606 OID 737902)
-- Dependencies: 787 787
-- Name: flash_versions_flash_version_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY flash_versions
    ADD CONSTRAINT flash_versions_flash_version_key UNIQUE (flash_version);


--
-- TOC entry 4531 (class 2606 OID 737900)
-- Dependencies: 787 787
-- Name: flash_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY flash_versions
    ADD CONSTRAINT flash_versions_pkey PRIMARY KEY (flash_version_id);


--
-- TOC entry 4454 (class 2606 OID 52094)
-- Dependencies: 627 627
-- Name: jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- TOC entry 4456 (class 2606 OID 52096)
-- Dependencies: 627 627
-- Name: jobs_uuid_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_uuid_key UNIQUE (uuid);


--
-- TOC entry 4596 (class 2606 OID 1142113)
-- Dependencies: 921 921 921 921
-- Name: nightly_builds_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY nightly_builds
    ADD CONSTRAINT nightly_builds_key PRIMARY KEY (product_version_id, build_date, days_out);


--
-- TOC entry 4519 (class 2606 OID 531741)
-- Dependencies: 744 744 744
-- Name: os_name_matches_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY os_name_matches
    ADD CONSTRAINT os_name_matches_key PRIMARY KEY (os_name, match_string);


--
-- TOC entry 4513 (class 2606 OID 531715)
-- Dependencies: 741 741
-- Name: os_names_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY os_names
    ADD CONSTRAINT os_names_pkey PRIMARY KEY (os_name);


--
-- TOC entry 4515 (class 2606 OID 531728)
-- Dependencies: 743 743 743 743
-- Name: os_versions_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY os_versions
    ADD CONSTRAINT os_versions_key UNIQUE (os_name, major_version, minor_version);


--
-- TOC entry 4517 (class 2606 OID 531726)
-- Dependencies: 743 743
-- Name: os_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY os_versions
    ADD CONSTRAINT os_versions_pkey PRIMARY KEY (os_version_id);


--
-- TOC entry 4418 (class 2606 OID 50717)
-- Dependencies: 583 583
-- Name: osdims_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY osdims
    ADD CONSTRAINT osdims_pkey PRIMARY KEY (id);


--
-- TOC entry 4422 (class 2606 OID 50725)
-- Dependencies: 585 585
-- Name: plugins_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY plugins
    ADD CONSTRAINT plugins_pkey PRIMARY KEY (id);


--
-- TOC entry 4566 (class 2606 OID 883143)
-- Dependencies: 852 852
-- Name: priority_jobs_1956_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_1956
    ADD CONSTRAINT priority_jobs_1956_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4568 (class 2606 OID 902403)
-- Dependencies: 855 855
-- Name: priority_jobs_2034_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2034
    ADD CONSTRAINT priority_jobs_2034_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4594 (class 2606 OID 1115743)
-- Dependencies: 910 910
-- Name: priority_jobs_2276_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2276
    ADD CONSTRAINT priority_jobs_2276_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4603 (class 2606 OID 1256164)
-- Dependencies: 955 955
-- Name: priority_jobs_2510_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2510
    ADD CONSTRAINT priority_jobs_2510_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4605 (class 2606 OID 1256169)
-- Dependencies: 956 956
-- Name: priority_jobs_2511_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2511
    ADD CONSTRAINT priority_jobs_2511_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4607 (class 2606 OID 1256174)
-- Dependencies: 957 957
-- Name: priority_jobs_2512_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2512
    ADD CONSTRAINT priority_jobs_2512_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4609 (class 2606 OID 1256179)
-- Dependencies: 958 958
-- Name: priority_jobs_2513_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2513
    ADD CONSTRAINT priority_jobs_2513_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4611 (class 2606 OID 1256184)
-- Dependencies: 959 959
-- Name: priority_jobs_2514_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2514
    ADD CONSTRAINT priority_jobs_2514_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4613 (class 2606 OID 1256189)
-- Dependencies: 960 960
-- Name: priority_jobs_2515_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2515
    ADD CONSTRAINT priority_jobs_2515_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4615 (class 2606 OID 1256194)
-- Dependencies: 961 961
-- Name: priority_jobs_2516_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2516
    ADD CONSTRAINT priority_jobs_2516_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4617 (class 2606 OID 1256199)
-- Dependencies: 962 962
-- Name: priority_jobs_2517_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2517
    ADD CONSTRAINT priority_jobs_2517_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4619 (class 2606 OID 1256204)
-- Dependencies: 963 963
-- Name: priority_jobs_2518_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2518
    ADD CONSTRAINT priority_jobs_2518_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4621 (class 2606 OID 1256209)
-- Dependencies: 964 964
-- Name: priority_jobs_2519_pkey; Type: CONSTRAINT; Schema: public; Owner: processor; Tablespace: 
--

ALTER TABLE ONLY priority_jobs_2519
    ADD CONSTRAINT priority_jobs_2519_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4460 (class 2606 OID 52098)
-- Dependencies: 631 631
-- Name: priorityjobs_logging_switch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY priorityjobs_logging_switch
    ADD CONSTRAINT priorityjobs_logging_switch_pkey PRIMARY KEY (log_jobs);


--
-- TOC entry 4458 (class 2606 OID 52100)
-- Dependencies: 629 629
-- Name: priorityjobs_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY priorityjobs
    ADD CONSTRAINT priorityjobs_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4541 (class 2606 OID 737936)
-- Dependencies: 792 792
-- Name: process_types_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY process_types
    ADD CONSTRAINT process_types_pkey PRIMARY KEY (process_type);


--
-- TOC entry 4424 (class 2606 OID 51028)
-- Dependencies: 599 599
-- Name: processors_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY processors
    ADD CONSTRAINT processors_pkey PRIMARY KEY (id);


--
-- TOC entry 4521 (class 2606 OID 531755)
-- Dependencies: 745 745 745 745
-- Name: product_adu_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_adu
    ADD CONSTRAINT product_adu_key PRIMARY KEY (product_version_id, adu_date, os_name);


--
-- TOC entry 4564 (class 2606 OID 880684)
-- Dependencies: 846 846 846 846
-- Name: product_info_changelog_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_info_changelog
    ADD CONSTRAINT product_info_changelog_key PRIMARY KEY (product_version_id, changed_on, user_name);


--
-- TOC entry 4574 (class 2606 OID 907824)
-- Dependencies: 860 860
-- Name: product_productid_map_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_productid_map
    ADD CONSTRAINT product_productid_map_pkey PRIMARY KEY (productid);


--
-- TOC entry 4509 (class 2606 OID 531684)
-- Dependencies: 739 739 739
-- Name: product_release_channels_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_release_channels
    ADD CONSTRAINT product_release_channels_key PRIMARY KEY (product_name, release_channel);


--
-- TOC entry 4489 (class 2606 OID 531567)
-- Dependencies: 731 731 731 731
-- Name: product_version_builds_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_version_builds
    ADD CONSTRAINT product_version_builds_key PRIMARY KEY (product_version_id, build_id, platform);


--
-- TOC entry 4482 (class 2606 OID 531550)
-- Dependencies: 730 730 730
-- Name: product_version_version_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_versions
    ADD CONSTRAINT product_version_version_key UNIQUE (product_name, version_string);


--
-- TOC entry 4485 (class 2606 OID 531548)
-- Dependencies: 730 730
-- Name: product_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_versions
    ADD CONSTRAINT product_versions_pkey PRIMARY KEY (product_version_id);


--
-- TOC entry 4427 (class 2606 OID 51031)
-- Dependencies: 601 601
-- Name: product_visibility_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_visibility
    ADD CONSTRAINT product_visibility_pkey PRIMARY KEY (productdims_id);


--
-- TOC entry 4392 (class 2606 OID 51035)
-- Dependencies: 560 560
-- Name: productdims_pkey1; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY productdims
    ADD CONSTRAINT productdims_pkey1 PRIMARY KEY (id);


--
-- TOC entry 4468 (class 2606 OID 267225)
-- Dependencies: 678 678
-- Name: productdims_version_sort_id_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY productdims_version_sort
    ADD CONSTRAINT productdims_version_sort_id_key UNIQUE (id);


--
-- TOC entry 4470 (class 2606 OID 267223)
-- Dependencies: 678 678 678
-- Name: productdims_version_sort_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY productdims_version_sort
    ADD CONSTRAINT productdims_version_sort_key PRIMARY KEY (product, version);


--
-- TOC entry 4576 (class 2606 OID 907826)
-- Dependencies: 860 860 860
-- Name: productid_map_key2; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY product_productid_map
    ADD CONSTRAINT productid_map_key2 UNIQUE (product_name, version_began);


--
-- TOC entry 4477 (class 2606 OID 531527)
-- Dependencies: 728 728
-- Name: products_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_name);


--
-- TOC entry 4580 (class 2606 OID 1052941)
-- Dependencies: 893 893 893 893
-- Name: rank_compare_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY rank_compare
    ADD CONSTRAINT rank_compare_key PRIMARY KEY (product_version_id, signature_id, rank_days);


--
-- TOC entry 4525 (class 2606 OID 737887)
-- Dependencies: 785 785
-- Name: reasons_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY reasons
    ADD CONSTRAINT reasons_pkey PRIMARY KEY (reason_id);


--
-- TOC entry 4527 (class 2606 OID 737889)
-- Dependencies: 785 785
-- Name: reasons_reason_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY reasons
    ADD CONSTRAINT reasons_reason_key UNIQUE (reason);


--
-- TOC entry 4491 (class 2606 OID 531580)
-- Dependencies: 732 732
-- Name: release_build_type_map_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY release_build_type_map
    ADD CONSTRAINT release_build_type_map_pkey PRIMARY KEY (release);


--
-- TOC entry 4511 (class 2606 OID 531702)
-- Dependencies: 740 740 740
-- Name: release_channel_matches_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY release_channel_matches
    ADD CONSTRAINT release_channel_matches_key PRIMARY KEY (release_channel, match_string);


--
-- TOC entry 4479 (class 2606 OID 531536)
-- Dependencies: 729 729
-- Name: release_channels_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY release_channels
    ADD CONSTRAINT release_channels_pkey PRIMARY KEY (release_channel);


--
-- TOC entry 4474 (class 2606 OID 722359)
-- Dependencies: 727 727 727 727 727 727 727
-- Name: release_raw_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY releases_raw
    ADD CONSTRAINT release_raw_key PRIMARY KEY (product_name, version, build_type, build_id, platform, repository);


--
-- TOC entry 4562 (class 2606 OID 833217)
-- Dependencies: 834 834
-- Name: report_partition_info_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY report_partition_info
    ADD CONSTRAINT report_partition_info_pkey PRIMARY KEY (table_name);


--
-- TOC entry 4543 (class 2606 OID 737944)
-- Dependencies: 793 793
-- Name: reports_clean_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY reports_clean
    ADD CONSTRAINT reports_clean_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4465 (class 2606 OID 231530)
-- Dependencies: 672 672
-- Name: reports_duplicates_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY reports_duplicates
    ADD CONSTRAINT reports_duplicates_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4545 (class 2606 OID 737952)
-- Dependencies: 794 794
-- Name: reports_user_info_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY reports_user_info
    ADD CONSTRAINT reports_user_info_pkey PRIMARY KEY (uuid);


--
-- TOC entry 4432 (class 2606 OID 51883)
-- Dependencies: 618 618
-- Name: server_status_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY server_status
    ADD CONSTRAINT server_status_pkey PRIMARY KEY (id);


--
-- TOC entry 4462 (class 2606 OID 180447)
-- Dependencies: 660 660
-- Name: session_id_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY sessions
    ADD CONSTRAINT session_id_pkey PRIMARY KEY (session_id);


--
-- TOC entry 4507 (class 2606 OID 531670)
-- Dependencies: 738 738
-- Name: signature_bugs_rollup_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY signature_bugs_rollup
    ADD CONSTRAINT signature_bugs_rollup_pkey PRIMARY KEY (signature_id);


--
-- TOC entry 4502 (class 2606 OID 531629)
-- Dependencies: 736 736 736
-- Name: signature_products_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY signature_products
    ADD CONSTRAINT signature_products_key PRIMARY KEY (signature_id, product_version_id);


--
-- TOC entry 4505 (class 2606 OID 531650)
-- Dependencies: 737 737 737
-- Name: signature_products_rollup_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY signature_products_rollup
    ADD CONSTRAINT signature_products_rollup_key PRIMARY KEY (signature_id, product_name);


--
-- TOC entry 4493 (class 2606 OID 531591)
-- Dependencies: 734 734
-- Name: signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY signatures
    ADD CONSTRAINT signatures_pkey PRIMARY KEY (signature_id);

ALTER TABLE signatures CLUSTER ON signatures_pkey;


--
-- TOC entry 4495 (class 2606 OID 531593)
-- Dependencies: 734 734
-- Name: signatures_signature_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY signatures
    ADD CONSTRAINT signatures_signature_key UNIQUE (signature);


--
-- TOC entry 4572 (class 2606 OID 1125138)
-- Dependencies: 859 859 859
-- Name: socorro_db_version_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY socorro_db_version_history
    ADD CONSTRAINT socorro_db_version_history_pkey PRIMARY KEY (version, upgraded_on);


--
-- TOC entry 4570 (class 2606 OID 907745)
-- Dependencies: 858 858
-- Name: socorro_db_version_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY socorro_db_version
    ADD CONSTRAINT socorro_db_version_pkey PRIMARY KEY (current_version);


--
-- TOC entry 4578 (class 2606 OID 907839)
-- Dependencies: 861 861 861 861 861
-- Name: special_product_platforms_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY special_product_platforms
    ADD CONSTRAINT special_product_platforms_key PRIMARY KEY (release_name, platform, repository, release_channel);


--
-- TOC entry 4497 (class 2606 OID 531606)
-- Dependencies: 735 735 735 735 735 735
-- Name: tcbs_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY tcbs
    ADD CONSTRAINT tcbs_key PRIMARY KEY (signature_id, report_date, product_version_id, process_type, release_channel);


--
-- TOC entry 4435 (class 2606 OID 52009)
-- Dependencies: 620 620
-- Name: top_crashes_by_signature2_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY top_crashes_by_signature
    ADD CONSTRAINT top_crashes_by_signature2_pkey PRIMARY KEY (id);


--
-- TOC entry 4442 (class 2606 OID 51937)
-- Dependencies: 622 622
-- Name: top_crashes_by_url2_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY top_crashes_by_url
    ADD CONSTRAINT top_crashes_by_url2_pkey PRIMARY KEY (id);


--
-- TOC entry 4447 (class 2606 OID 51946)
-- Dependencies: 624 624 624
-- Name: top_crashes_by_url_signature2_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY top_crashes_by_url_signature
    ADD CONSTRAINT top_crashes_by_url_signature2_pkey PRIMARY KEY (top_crashes_by_url_id, signature);


--
-- TOC entry 4599 (class 2606 OID 1159760)
-- Dependencies: 928 928 928
-- Name: transform_rules_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY transform_rules
    ADD CONSTRAINT transform_rules_key UNIQUE (category, rule_order) DEFERRABLE INITIALLY DEFERRED;


--
-- TOC entry 4601 (class 2606 OID 1159758)
-- Dependencies: 928 928
-- Name: transform_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY transform_rules
    ADD CONSTRAINT transform_rules_pkey PRIMARY KEY (transform_rule_id);


--
-- TOC entry 4558 (class 2606 OID 833191)
-- Dependencies: 833 833
-- Name: uptime_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY uptime_levels
    ADD CONSTRAINT uptime_levels_pkey PRIMARY KEY (uptime_level);


--
-- TOC entry 4560 (class 2606 OID 833193)
-- Dependencies: 833 833
-- Name: uptime_levels_uptime_string_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY uptime_levels
    ADD CONSTRAINT uptime_levels_uptime_string_key UNIQUE (uptime_string);


--
-- TOC entry 4449 (class 2606 OID 51901)
-- Dependencies: 625 625
-- Name: urldims_pkey1; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY urldims
    ADD CONSTRAINT urldims_pkey1 PRIMARY KEY (id);


--
-- TOC entry 4556 (class 2606 OID 833155)
-- Dependencies: 831 831 831
-- Name: windows_version_key; Type: CONSTRAINT; Schema: public; Owner: breakpad_rw; Tablespace: 
--

ALTER TABLE ONLY windows_versions
    ADD CONSTRAINT windows_version_key UNIQUE (major_version, minor_version);


--
-- TOC entry 4400 (class 1259 OID 267209)
-- Dependencies: 563 563 3769 3769 563 3769 563
-- Name: builds_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE UNIQUE INDEX builds_key ON builds USING btree (product, version, platform, buildid);


--
-- TOC entry 4546 (class 1259 OID 737980)
-- Dependencies: 796
-- Name: daily_hangs_browser_signature_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_browser_signature_id ON daily_hangs USING btree (browser_signature_id);


--
-- TOC entry 4547 (class 1259 OID 737982)
-- Dependencies: 796
-- Name: daily_hangs_flash_version_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_flash_version_id ON daily_hangs USING btree (flash_version_id);


--
-- TOC entry 4548 (class 1259 OID 737983)
-- Dependencies: 796
-- Name: daily_hangs_hang_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_hang_id ON daily_hangs USING btree (hang_id);


--
-- TOC entry 4551 (class 1259 OID 737981)
-- Dependencies: 796
-- Name: daily_hangs_plugin_signature_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_plugin_signature_id ON daily_hangs USING btree (plugin_signature_id);


--
-- TOC entry 4552 (class 1259 OID 737979)
-- Dependencies: 796
-- Name: daily_hangs_product_version_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_product_version_id ON daily_hangs USING btree (product_version_id);


--
-- TOC entry 4553 (class 1259 OID 737977)
-- Dependencies: 796
-- Name: daily_hangs_report_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_report_date ON daily_hangs USING btree (report_date);


--
-- TOC entry 4554 (class 1259 OID 737978)
-- Dependencies: 796
-- Name: daily_hangs_uuid; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX daily_hangs_uuid ON daily_hangs USING btree (uuid);


--
-- TOC entry 4407 (class 1259 OID 50447)
-- Dependencies: 566 566
-- Name: email_campaigns_product_signature_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX email_campaigns_product_signature_key ON email_campaigns USING btree (product, signature);


--
-- TOC entry 4624 (class 1259 OID 1256301)
-- Dependencies: 965
-- Name: explosiveness_product_version_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX explosiveness_product_version_id ON explosiveness USING btree (product_version_id);


--
-- TOC entry 4625 (class 1259 OID 1256302)
-- Dependencies: 965
-- Name: explosiveness_signature_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX explosiveness_signature_id ON explosiveness USING btree (signature_id);


--
-- TOC entry 4397 (class 1259 OID 50437)
-- Dependencies: 561
-- Name: idx_bug_associations_bug_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX idx_bug_associations_bug_id ON bug_associations USING btree (bug_id);


--
-- TOC entry 4430 (class 1259 OID 51884)
-- Dependencies: 618 618
-- Name: idx_server_status_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX idx_server_status_date ON server_status USING btree (date_created, id);


--
-- TOC entry 4451 (class 1259 OID 52101)
-- Dependencies: 627 627
-- Name: jobs_completeddatetime_queueddatetime_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX jobs_completeddatetime_queueddatetime_key ON jobs USING btree (completeddatetime, queueddatetime);


--
-- TOC entry 4452 (class 1259 OID 52102)
-- Dependencies: 627 627
-- Name: jobs_owner_starteddatetime_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX jobs_owner_starteddatetime_key ON jobs USING btree (owner, starteddatetime);

ALTER TABLE jobs CLUSTER ON jobs_owner_starteddatetime_key;


--
-- TOC entry 4597 (class 1259 OID 1142114)
-- Dependencies: 921 921
-- Name: nightly_builds_product_version_id_report_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX nightly_builds_product_version_id_report_date ON nightly_builds USING btree (product_version_id, report_date);


--
-- TOC entry 4416 (class 1259 OID 50718)
-- Dependencies: 583 583
-- Name: osdims_name_version_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX osdims_name_version_key ON osdims USING btree (os_name, os_version);


--
-- TOC entry 4480 (class 1259 OID 656055)
-- Dependencies: 730 730 3769 730 730 3769
-- Name: product_version_unique_beta; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE UNIQUE INDEX product_version_unique_beta ON product_versions USING btree (product_name, release_version, beta_number) WHERE (beta_number IS NOT NULL);


--
-- TOC entry 4483 (class 1259 OID 531558)
-- Dependencies: 730
-- Name: product_versions_major_version; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX product_versions_major_version ON product_versions USING btree (major_version);


--
-- TOC entry 4486 (class 1259 OID 531557)
-- Dependencies: 730 3769
-- Name: product_versions_product_name; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX product_versions_product_name ON product_versions USING btree (product_name);


--
-- TOC entry 4487 (class 1259 OID 531559)
-- Dependencies: 730
-- Name: product_versions_version_sort; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX product_versions_version_sort ON product_versions USING btree (version_sort);


--
-- TOC entry 4425 (class 1259 OID 51032)
-- Dependencies: 601
-- Name: product_visibility_end_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX product_visibility_end_date ON product_visibility USING btree (end_date);


--
-- TOC entry 4428 (class 1259 OID 51033)
-- Dependencies: 601
-- Name: product_visibility_start_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX product_visibility_start_date ON product_visibility USING btree (start_date);


--
-- TOC entry 4393 (class 1259 OID 267175)
-- Dependencies: 560 3769 3769 560
-- Name: productdims_product_version_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE UNIQUE INDEX productdims_product_version_key ON productdims USING btree (product, version);


--
-- TOC entry 4394 (class 1259 OID 267176)
-- Dependencies: 560 560 3769
-- Name: productdims_sort_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX productdims_sort_key ON productdims USING btree (product, sort_key);


--
-- TOC entry 4581 (class 1259 OID 1052942)
-- Dependencies: 893 893
-- Name: rank_compare_product_version_id_rank_report_count; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX rank_compare_product_version_id_rank_report_count ON rank_compare USING btree (product_version_id, rank_report_count);


--
-- TOC entry 4582 (class 1259 OID 1052943)
-- Dependencies: 893
-- Name: rank_compare_signature_id; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX rank_compare_signature_id ON rank_compare USING btree (signature_id);


--
-- TOC entry 4429 (class 1259 OID 969993)
-- Dependencies: 603 603 603 603 603
-- Name: raw_adu_1_idx; Type: INDEX; Schema: public; Owner: breakpad_metrics; Tablespace: 
--

CREATE INDEX raw_adu_1_idx ON raw_adu USING btree (date, product_name, product_version, product_os_platform, product_os_version);


--
-- TOC entry 4475 (class 1259 OID 722360)
-- Dependencies: 727 727 1037
-- Name: releases_raw_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX releases_raw_date ON releases_raw USING btree (build_date(build_id));


--
-- TOC entry 4463 (class 1259 OID 231531)
-- Dependencies: 672
-- Name: reports_duplicates_leader; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX reports_duplicates_leader ON reports_duplicates USING btree (duplicate_of);


--
-- TOC entry 4466 (class 1259 OID 737960)
-- Dependencies: 672 672
-- Name: reports_duplicates_timestamp; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX reports_duplicates_timestamp ON reports_duplicates USING btree (date_processed, uuid);


--
-- TOC entry 4503 (class 1259 OID 531640)
-- Dependencies: 736
-- Name: signature_products_product_version; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX signature_products_product_version ON signature_products USING btree (product_version_id);


--
-- TOC entry 4498 (class 1259 OID 531624)
-- Dependencies: 735 735
-- Name: tcbs_product_version; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX tcbs_product_version ON tcbs USING btree (product_version_id, report_date);


--
-- TOC entry 4499 (class 1259 OID 531623)
-- Dependencies: 735
-- Name: tcbs_report_date; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX tcbs_report_date ON tcbs USING btree (report_date);


--
-- TOC entry 4500 (class 1259 OID 531622)
-- Dependencies: 735
-- Name: tcbs_signature; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX tcbs_signature ON tcbs USING btree (signature_id);


--
-- TOC entry 4433 (class 1259 OID 52030)
-- Dependencies: 620
-- Name: top_crashes_by_signature2_osdims_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_signature2_osdims_key ON top_crashes_by_signature USING btree (osdims_id);


--
-- TOC entry 4436 (class 1259 OID 52032)
-- Dependencies: 620 620
-- Name: top_crashes_by_signature2_productdims_window_end_idx; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_signature2_productdims_window_end_idx ON top_crashes_by_signature USING btree (productdims_id, window_end DESC);


--
-- TOC entry 4437 (class 1259 OID 52031)
-- Dependencies: 620
-- Name: top_crashes_by_signature2_signature_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_signature2_signature_key ON top_crashes_by_signature USING btree (signature);


--
-- TOC entry 4438 (class 1259 OID 52033)
-- Dependencies: 620 620
-- Name: top_crashes_by_signature2_window_end_productdims_id_idx; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_signature2_window_end_productdims_id_idx ON top_crashes_by_signature USING btree (window_end DESC, productdims_id);


--
-- TOC entry 4439 (class 1259 OID 51954)
-- Dependencies: 622
-- Name: top_crashes_by_url2_count_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_url2_count_key ON top_crashes_by_url USING btree (count);


--
-- TOC entry 4440 (class 1259 OID 51955)
-- Dependencies: 622
-- Name: top_crashes_by_url2_osdims_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_url2_osdims_key ON top_crashes_by_url USING btree (osdims_id);


--
-- TOC entry 4443 (class 1259 OID 52005)
-- Dependencies: 622
-- Name: top_crashes_by_url2_productdims_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_url2_productdims_key ON top_crashes_by_url USING btree (productdims_id);


--
-- TOC entry 4444 (class 1259 OID 52006)
-- Dependencies: 622
-- Name: top_crashes_by_url2_urldims_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_url2_urldims_key ON top_crashes_by_url USING btree (urldims_id);


--
-- TOC entry 4445 (class 1259 OID 52007)
-- Dependencies: 622 622
-- Name: top_crashes_by_url2_window_end_window_size_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE INDEX top_crashes_by_url2_window_end_window_size_key ON top_crashes_by_url USING btree (window_end, window_size);


--
-- TOC entry 4450 (class 1259 OID 51902)
-- Dependencies: 625 625
-- Name: urldims_url_domain_key; Type: INDEX; Schema: public; Owner: breakpad_rw; Tablespace: 
--

CREATE UNIQUE INDEX urldims_url_domain_key ON urldims USING btree (url, domain);


--
-- TOC entry 4653 (class 2620 OID 52103)
-- Dependencies: 979 629
-- Name: log_priorityjobs; Type: TRIGGER; Schema: public; Owner: breakpad_rw
--

CREATE TRIGGER log_priorityjobs AFTER INSERT ON priorityjobs FOR EACH ROW EXECUTE PROCEDURE log_priorityjobs();


--
-- TOC entry 4656 (class 2620 OID 1159762)
-- Dependencies: 928 1070
-- Name: transform_rules_insert_order; Type: TRIGGER; Schema: public; Owner: breakpad_rw
--

CREATE TRIGGER transform_rules_insert_order BEFORE INSERT ON transform_rules FOR EACH ROW EXECUTE PROCEDURE transform_rules_insert_order();


--
-- TOC entry 4657 (class 2620 OID 1159763)
-- Dependencies: 928 1074 928 928
-- Name: transform_rules_update_order; Type: TRIGGER; Schema: public; Owner: breakpad_rw
--

CREATE TRIGGER transform_rules_update_order AFTER UPDATE OF rule_order, category ON transform_rules FOR EACH ROW EXECUTE PROCEDURE transform_rules_update_order();


--
-- TOC entry 4652 (class 2620 OID 880663)
-- Dependencies: 560 1053
-- Name: version_sort_trigger; Type: TRIGGER; Schema: public; Owner: breakpad_rw
--

CREATE TRIGGER version_sort_trigger BEFORE INSERT OR UPDATE ON productdims FOR EACH ROW EXECUTE PROCEDURE version_sort_trigger();


--
-- TOC entry 4655 (class 2620 OID 267237)
-- Dependencies: 678 1029
-- Name: version_sort_update_trigger_after; Type: TRIGGER; Schema: public; Owner: breakpad_rw
--

CREATE TRIGGER version_sort_update_trigger_after AFTER UPDATE ON productdims_version_sort FOR EACH ROW EXECUTE PROCEDURE version_sort_update_trigger_after();


--
-- TOC entry 4654 (class 2620 OID 267236)
-- Dependencies: 678 1028
-- Name: version_sort_update_trigger_before; Type: TRIGGER; Schema: public; Owner: breakpad_rw
--

CREATE TRIGGER version_sort_update_trigger_before BEFORE UPDATE ON productdims_version_sort FOR EACH ROW EXECUTE PROCEDURE version_sort_update_trigger_before();


--
-- TOC entry 4626 (class 2606 OID 160071)
-- Dependencies: 562 4398 561
-- Name: bug_associations_bugs_fk; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY bug_associations
    ADD CONSTRAINT bug_associations_bugs_fk FOREIGN KEY (bug_id) REFERENCES bugs(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4649 (class 2606 OID 1101618)
-- Dependencies: 902 901 4585
-- Name: correlation_addons_correlation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY correlation_addons
    ADD CONSTRAINT correlation_addons_correlation_id_fkey FOREIGN KEY (correlation_id) REFERENCES correlations(correlation_id) ON DELETE CASCADE;


--
-- TOC entry 4651 (class 2606 OID 1101646)
-- Dependencies: 4585 901 904
-- Name: correlation_cores_correlation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY correlation_cores
    ADD CONSTRAINT correlation_cores_correlation_id_fkey FOREIGN KEY (correlation_id) REFERENCES correlations(correlation_id) ON DELETE CASCADE;


--
-- TOC entry 4650 (class 2606 OID 1101632)
-- Dependencies: 4585 901 903
-- Name: correlation_modules_correlation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY correlation_modules
    ADD CONSTRAINT correlation_modules_correlation_id_fkey FOREIGN KEY (correlation_id) REFERENCES correlations(correlation_id) ON DELETE CASCADE;


--
-- TOC entry 4627 (class 2606 OID 50448)
-- Dependencies: 4405 567 566
-- Name: email_campaigns_contacts_email_campaigns_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY email_campaigns_contacts
    ADD CONSTRAINT email_campaigns_contacts_email_campaigns_id_fkey FOREIGN KEY (email_campaigns_id) REFERENCES email_campaigns(id);


--
-- TOC entry 4628 (class 2606 OID 50459)
-- Dependencies: 567 4412 569
-- Name: email_campaigns_contacts_email_contacts_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY email_campaigns_contacts
    ADD CONSTRAINT email_campaigns_contacts_email_contacts_id_fkey FOREIGN KEY (email_contacts_id) REFERENCES email_contacts(id);


--
-- TOC entry 4633 (class 2606 OID 52104)
-- Dependencies: 599 4423 627
-- Name: jobs_owner_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_owner_fkey FOREIGN KEY (owner) REFERENCES processors(id) ON DELETE CASCADE;


--
-- TOC entry 4647 (class 2606 OID 531742)
-- Dependencies: 3635 744 4512 741
-- Name: os_name_matches_os_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY os_name_matches
    ADD CONSTRAINT os_name_matches_os_name_fkey FOREIGN KEY (os_name) REFERENCES os_names(os_name);


--
-- TOC entry 4646 (class 2606 OID 531729)
-- Dependencies: 4512 3635 741 743
-- Name: os_versions_os_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY os_versions
    ADD CONSTRAINT os_versions_os_name_fkey FOREIGN KEY (os_name) REFERENCES os_names(os_name);


--
-- TOC entry 4648 (class 2606 OID 907827)
-- Dependencies: 860 728 4476 3635
-- Name: product_productid_map_product_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_productid_map
    ADD CONSTRAINT product_productid_map_product_name_fkey FOREIGN KEY (product_name) REFERENCES products(product_name) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4643 (class 2606 OID 531685)
-- Dependencies: 3635 739 728 4476
-- Name: product_release_channels_product_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_release_channels
    ADD CONSTRAINT product_release_channels_product_name_fkey FOREIGN KEY (product_name) REFERENCES products(product_name);


--
-- TOC entry 4644 (class 2606 OID 531690)
-- Dependencies: 4478 729 739 3635
-- Name: product_release_channels_release_channel_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_release_channels
    ADD CONSTRAINT product_release_channels_release_channel_fkey FOREIGN KEY (release_channel) REFERENCES release_channels(release_channel);


--
-- TOC entry 4636 (class 2606 OID 1125141)
-- Dependencies: 730 731 4484
-- Name: product_version_builds_product_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_version_builds
    ADD CONSTRAINT product_version_builds_product_version_id_fkey FOREIGN KEY (product_version_id) REFERENCES product_versions(product_version_id) ON DELETE CASCADE;


--
-- TOC entry 4635 (class 2606 OID 531551)
-- Dependencies: 3635 4476 728 730
-- Name: product_versions_product_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_versions
    ADD CONSTRAINT product_versions_product_name_fkey FOREIGN KEY (product_name) REFERENCES products(product_name);


--
-- TOC entry 4629 (class 2606 OID 51043)
-- Dependencies: 601 4391 560
-- Name: product_visibility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY product_visibility
    ADD CONSTRAINT product_visibility_id_fkey FOREIGN KEY (productdims_id) REFERENCES productdims(id) ON DELETE CASCADE;


--
-- TOC entry 4630 (class 2606 OID 52069)
-- Dependencies: 4391 620 560
-- Name: productdims_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY top_crashes_by_signature
    ADD CONSTRAINT productdims_id_fkey FOREIGN KEY (productdims_id) REFERENCES productdims(id) ON DELETE CASCADE;


--
-- TOC entry 4634 (class 2606 OID 267226)
-- Dependencies: 560 4393 3635 3635 678 678 560
-- Name: productdims_product_version_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY productdims_version_sort
    ADD CONSTRAINT productdims_product_version_fkey FOREIGN KEY (product, version) REFERENCES productdims(product, version) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4645 (class 2606 OID 531703)
-- Dependencies: 3635 729 740 4478
-- Name: release_channel_matches_release_channel_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY release_channel_matches
    ADD CONSTRAINT release_channel_matches_release_channel_fkey FOREIGN KEY (release_channel) REFERENCES release_channels(release_channel);


--
-- TOC entry 4642 (class 2606 OID 531671)
-- Dependencies: 738 734 4492
-- Name: signature_bugs_rollup_signature_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY signature_bugs_rollup
    ADD CONSTRAINT signature_bugs_rollup_signature_id_fkey FOREIGN KEY (signature_id) REFERENCES signatures(signature_id);


--
-- TOC entry 4641 (class 2606 OID 531656)
-- Dependencies: 4476 728 3635 737
-- Name: signature_products_rollup_product_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY signature_products_rollup
    ADD CONSTRAINT signature_products_rollup_product_name_fkey FOREIGN KEY (product_name) REFERENCES products(product_name);


--
-- TOC entry 4640 (class 2606 OID 531651)
-- Dependencies: 737 4492 734
-- Name: signature_products_rollup_signature_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY signature_products_rollup
    ADD CONSTRAINT signature_products_rollup_signature_id_fkey FOREIGN KEY (signature_id) REFERENCES signatures(signature_id);


--
-- TOC entry 4639 (class 2606 OID 531630)
-- Dependencies: 736 4492 734
-- Name: signature_products_signature_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY signature_products
    ADD CONSTRAINT signature_products_signature_id_fkey FOREIGN KEY (signature_id) REFERENCES signatures(signature_id);


--
-- TOC entry 4638 (class 2606 OID 531617)
-- Dependencies: 735 4478 3635 729
-- Name: tcbs_release_channel_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY tcbs
    ADD CONSTRAINT tcbs_release_channel_fkey FOREIGN KEY (release_channel) REFERENCES release_channels(release_channel);


--
-- TOC entry 4637 (class 2606 OID 531607)
-- Dependencies: 735 734 4492
-- Name: tcbs_signature_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY tcbs
    ADD CONSTRAINT tcbs_signature_id_fkey FOREIGN KEY (signature_id) REFERENCES signatures(signature_id);


--
-- TOC entry 4631 (class 2606 OID 52015)
-- Dependencies: 622 560 4391
-- Name: top_crashes_by_url_productdims_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY top_crashes_by_url
    ADD CONSTRAINT top_crashes_by_url_productdims_id_fkey FOREIGN KEY (productdims_id) REFERENCES productdims(id) ON DELETE CASCADE;


--
-- TOC entry 4632 (class 2606 OID 52025)
-- Dependencies: 4441 624 622
-- Name: top_crashes_by_url_signature_fkey; Type: FK CONSTRAINT; Schema: public; Owner: breakpad_rw
--

ALTER TABLE ONLY top_crashes_by_url_signature
    ADD CONSTRAINT top_crashes_by_url_signature_fkey FOREIGN KEY (top_crashes_by_url_id) REFERENCES top_crashes_by_url(id) ON DELETE CASCADE;


--
-- TOC entry 4662 (class 0 OID 0)
-- Dependencies: 9
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- TOC entry 4663 (class 0 OID 0)
-- Dependencies: 2923
-- Name: plpgsql; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON LANGUAGE plpgsql FROM PUBLIC;
REVOKE ALL ON LANGUAGE plpgsql FROM postgres;
GRANT ALL ON LANGUAGE plpgsql TO postgres;
GRANT ALL ON LANGUAGE plpgsql TO PUBLIC;
GRANT ALL ON LANGUAGE plpgsql TO breakpad_rw;


--
-- TOC entry 4664 (class 0 OID 0)
-- Dependencies: 986
-- Name: pg_stat_statements_reset(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION pg_stat_statements_reset() FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_stat_statements_reset() FROM postgres;
GRANT ALL ON FUNCTION pg_stat_statements_reset() TO postgres;


--
-- TOC entry 4665 (class 0 OID 0)
-- Dependencies: 789
-- Name: addresses; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE addresses FROM PUBLIC;
REVOKE ALL ON TABLE addresses FROM breakpad_rw;
GRANT ALL ON TABLE addresses TO breakpad_rw;
GRANT SELECT ON TABLE addresses TO breakpad_ro;
GRANT SELECT ON TABLE addresses TO breakpad;
GRANT ALL ON TABLE addresses TO monitor;
GRANT SELECT ON TABLE addresses TO analyst;


--
-- TOC entry 4667 (class 0 OID 0)
-- Dependencies: 558
-- Name: alexa_topsites; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE alexa_topsites FROM PUBLIC;
REVOKE ALL ON TABLE alexa_topsites FROM breakpad_rw;
GRANT ALL ON TABLE alexa_topsites TO breakpad_rw;
GRANT SELECT ON TABLE alexa_topsites TO monitoring;
GRANT SELECT ON TABLE alexa_topsites TO breakpad_ro;
GRANT SELECT ON TABLE alexa_topsites TO breakpad;


--
-- TOC entry 4668 (class 0 OID 0)
-- Dependencies: 559
-- Name: bloat; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE bloat FROM PUBLIC;
REVOKE ALL ON TABLE bloat FROM postgres;
GRANT ALL ON TABLE bloat TO postgres;
GRANT SELECT ON TABLE bloat TO monitoring;
GRANT SELECT ON TABLE bloat TO breakpad_ro;
GRANT SELECT ON TABLE bloat TO breakpad;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bloat TO breakpad_rw;


--
-- TOC entry 4669 (class 0 OID 0)
-- Dependencies: 730
-- Name: product_versions; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_versions FROM PUBLIC;
REVOKE ALL ON TABLE product_versions FROM breakpad_rw;
GRANT ALL ON TABLE product_versions TO breakpad_rw;
GRANT SELECT ON TABLE product_versions TO breakpad_ro;
GRANT SELECT ON TABLE product_versions TO breakpad;
GRANT ALL ON TABLE product_versions TO monitor;
GRANT SELECT ON TABLE product_versions TO analyst;


--
-- TOC entry 4671 (class 0 OID 0)
-- Dependencies: 602
-- Name: productdims_id_seq1; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE productdims_id_seq1 FROM PUBLIC;
REVOKE ALL ON SEQUENCE productdims_id_seq1 FROM breakpad_rw;
GRANT ALL ON SEQUENCE productdims_id_seq1 TO breakpad_rw;
GRANT SELECT ON SEQUENCE productdims_id_seq1 TO breakpad;


--
-- TOC entry 4672 (class 0 OID 0)
-- Dependencies: 560
-- Name: productdims; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE productdims FROM PUBLIC;
REVOKE ALL ON TABLE productdims FROM breakpad_rw;
GRANT ALL ON TABLE productdims TO breakpad_rw;
GRANT SELECT ON TABLE productdims TO monitoring;
GRANT SELECT ON TABLE productdims TO breakpad_ro;
GRANT SELECT ON TABLE productdims TO breakpad;


--
-- TOC entry 4673 (class 0 OID 0)
-- Dependencies: 677
-- Name: branches; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE branches FROM PUBLIC;
REVOKE ALL ON TABLE branches FROM breakpad_rw;
GRANT ALL ON TABLE branches TO breakpad_rw;
GRANT SELECT ON TABLE branches TO breakpad_ro;
GRANT SELECT ON TABLE branches TO breakpad;


--
-- TOC entry 4674 (class 0 OID 0)
-- Dependencies: 561
-- Name: bug_associations; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE bug_associations FROM PUBLIC;
REVOKE ALL ON TABLE bug_associations FROM breakpad_rw;
GRANT ALL ON TABLE bug_associations TO breakpad_rw;
GRANT SELECT ON TABLE bug_associations TO monitoring;
GRANT SELECT ON TABLE bug_associations TO breakpad_ro;
GRANT SELECT ON TABLE bug_associations TO breakpad;
GRANT SELECT ON TABLE bug_associations TO analyst;


--
-- TOC entry 4675 (class 0 OID 0)
-- Dependencies: 562
-- Name: bugs; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE bugs FROM PUBLIC;
REVOKE ALL ON TABLE bugs FROM breakpad_rw;
GRANT ALL ON TABLE bugs TO breakpad_rw;
GRANT SELECT ON TABLE bugs TO monitoring;
GRANT SELECT ON TABLE bugs TO breakpad_ro;
GRANT SELECT ON TABLE bugs TO breakpad;
GRANT SELECT ON TABLE bugs TO analyst;


--
-- TOC entry 4676 (class 0 OID 0)
-- Dependencies: 563
-- Name: builds; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE builds FROM PUBLIC;
REVOKE ALL ON TABLE builds FROM breakpad_rw;
GRANT ALL ON TABLE builds TO breakpad_rw;
GRANT SELECT ON TABLE builds TO monitoring;
GRANT SELECT ON TABLE builds TO breakpad_ro;
GRANT SELECT ON TABLE builds TO breakpad;


--
-- TOC entry 4677 (class 0 OID 0)
-- Dependencies: 902
-- Name: correlation_addons; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE correlation_addons FROM PUBLIC;
REVOKE ALL ON TABLE correlation_addons FROM breakpad_rw;
GRANT ALL ON TABLE correlation_addons TO breakpad_rw;
GRANT SELECT ON TABLE correlation_addons TO breakpad_ro;
GRANT SELECT ON TABLE correlation_addons TO breakpad;
GRANT ALL ON TABLE correlation_addons TO monitor;
GRANT SELECT ON TABLE correlation_addons TO analyst;


--
-- TOC entry 4678 (class 0 OID 0)
-- Dependencies: 904
-- Name: correlation_cores; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE correlation_cores FROM PUBLIC;
REVOKE ALL ON TABLE correlation_cores FROM breakpad_rw;
GRANT ALL ON TABLE correlation_cores TO breakpad_rw;
GRANT SELECT ON TABLE correlation_cores TO breakpad_ro;
GRANT SELECT ON TABLE correlation_cores TO breakpad;
GRANT ALL ON TABLE correlation_cores TO monitor;
GRANT SELECT ON TABLE correlation_cores TO analyst;


--
-- TOC entry 4679 (class 0 OID 0)
-- Dependencies: 903
-- Name: correlation_modules; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE correlation_modules FROM PUBLIC;
REVOKE ALL ON TABLE correlation_modules FROM breakpad_rw;
GRANT ALL ON TABLE correlation_modules TO breakpad_rw;
GRANT SELECT ON TABLE correlation_modules TO breakpad_ro;
GRANT SELECT ON TABLE correlation_modules TO breakpad;
GRANT ALL ON TABLE correlation_modules TO monitor;
GRANT SELECT ON TABLE correlation_modules TO analyst;


--
-- TOC entry 4680 (class 0 OID 0)
-- Dependencies: 901
-- Name: correlations; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE correlations FROM PUBLIC;
REVOKE ALL ON TABLE correlations FROM breakpad_rw;
GRANT ALL ON TABLE correlations TO breakpad_rw;
GRANT SELECT ON TABLE correlations TO breakpad_ro;
GRANT SELECT ON TABLE correlations TO breakpad;
GRANT ALL ON TABLE correlations TO monitor;
GRANT SELECT ON TABLE correlations TO analyst;


--
-- TOC entry 4682 (class 0 OID 0)
-- Dependencies: 708
-- Name: cronjobs; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE cronjobs FROM PUBLIC;
REVOKE ALL ON TABLE cronjobs FROM breakpad_rw;
GRANT ALL ON TABLE cronjobs TO breakpad_rw;
GRANT SELECT ON TABLE cronjobs TO breakpad_ro;
GRANT ALL ON TABLE cronjobs TO monitor;
GRANT SELECT ON TABLE cronjobs TO breakpad;


--
-- TOC entry 4683 (class 0 OID 0)
-- Dependencies: 746
-- Name: daily_crash_codes; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE daily_crash_codes FROM PUBLIC;
REVOKE ALL ON TABLE daily_crash_codes FROM breakpad_rw;
GRANT ALL ON TABLE daily_crash_codes TO breakpad_rw;
GRANT SELECT ON TABLE daily_crash_codes TO breakpad_ro;
GRANT SELECT ON TABLE daily_crash_codes TO breakpad;
GRANT ALL ON TABLE daily_crash_codes TO monitor;
GRANT SELECT ON TABLE daily_crash_codes TO analyst;


--
-- TOC entry 4684 (class 0 OID 0)
-- Dependencies: 564
-- Name: daily_crashes; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE daily_crashes FROM PUBLIC;
REVOKE ALL ON TABLE daily_crashes FROM breakpad_rw;
GRANT ALL ON TABLE daily_crashes TO breakpad_rw;
GRANT SELECT ON TABLE daily_crashes TO monitoring;
GRANT SELECT ON TABLE daily_crashes TO breakpad_ro;
GRANT SELECT ON TABLE daily_crashes TO breakpad;
GRANT SELECT ON TABLE daily_crashes TO analyst;


--
-- TOC entry 4686 (class 0 OID 0)
-- Dependencies: 565
-- Name: daily_crashes_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE daily_crashes_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE daily_crashes_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE daily_crashes_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE daily_crashes_id_seq TO breakpad;


--
-- TOC entry 4687 (class 0 OID 0)
-- Dependencies: 796
-- Name: daily_hangs; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE daily_hangs FROM PUBLIC;
REVOKE ALL ON TABLE daily_hangs FROM breakpad_rw;
GRANT ALL ON TABLE daily_hangs TO breakpad_rw;
GRANT SELECT ON TABLE daily_hangs TO breakpad_ro;
GRANT SELECT ON TABLE daily_hangs TO breakpad;
GRANT ALL ON TABLE daily_hangs TO monitor;
GRANT SELECT ON TABLE daily_hangs TO analyst;


--
-- TOC entry 4688 (class 0 OID 0)
-- Dependencies: 791
-- Name: domains; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE domains FROM PUBLIC;
REVOKE ALL ON TABLE domains FROM breakpad_rw;
GRANT ALL ON TABLE domains TO breakpad_rw;
GRANT SELECT ON TABLE domains TO breakpad_ro;
GRANT SELECT ON TABLE domains TO breakpad;
GRANT ALL ON TABLE domains TO monitor;
GRANT SELECT ON TABLE domains TO analyst;


--
-- TOC entry 4690 (class 0 OID 0)
-- Dependencies: 566
-- Name: email_campaigns; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE email_campaigns FROM PUBLIC;
REVOKE ALL ON TABLE email_campaigns FROM breakpad_rw;
GRANT ALL ON TABLE email_campaigns TO breakpad_rw;
GRANT SELECT ON TABLE email_campaigns TO monitoring;
GRANT SELECT ON TABLE email_campaigns TO breakpad_ro;
GRANT SELECT ON TABLE email_campaigns TO breakpad;


--
-- TOC entry 4691 (class 0 OID 0)
-- Dependencies: 567
-- Name: email_campaigns_contacts; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE email_campaigns_contacts FROM PUBLIC;
REVOKE ALL ON TABLE email_campaigns_contacts FROM breakpad_rw;
GRANT ALL ON TABLE email_campaigns_contacts TO breakpad_rw;
GRANT SELECT ON TABLE email_campaigns_contacts TO monitoring;
GRANT SELECT ON TABLE email_campaigns_contacts TO breakpad_ro;
GRANT SELECT ON TABLE email_campaigns_contacts TO breakpad;


--
-- TOC entry 4693 (class 0 OID 0)
-- Dependencies: 568
-- Name: email_campaigns_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE email_campaigns_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE email_campaigns_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE email_campaigns_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE email_campaigns_id_seq TO breakpad;


--
-- TOC entry 4694 (class 0 OID 0)
-- Dependencies: 569
-- Name: email_contacts; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE email_contacts FROM PUBLIC;
REVOKE ALL ON TABLE email_contacts FROM breakpad_rw;
GRANT ALL ON TABLE email_contacts TO breakpad_rw;
GRANT SELECT ON TABLE email_contacts TO monitoring;
GRANT SELECT ON TABLE email_contacts TO breakpad_ro;
GRANT SELECT ON TABLE email_contacts TO breakpad;


--
-- TOC entry 4696 (class 0 OID 0)
-- Dependencies: 570
-- Name: email_contacts_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE email_contacts_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE email_contacts_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE email_contacts_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE email_contacts_id_seq TO breakpad;


--
-- TOC entry 4697 (class 0 OID 0)
-- Dependencies: 965
-- Name: explosiveness; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE explosiveness FROM PUBLIC;
REVOKE ALL ON TABLE explosiveness FROM breakpad_rw;
GRANT ALL ON TABLE explosiveness TO breakpad_rw;
GRANT SELECT ON TABLE explosiveness TO breakpad_ro;
GRANT SELECT ON TABLE explosiveness TO breakpad;
GRANT ALL ON TABLE explosiveness TO monitor;


--
-- TOC entry 4698 (class 0 OID 0)
-- Dependencies: 571
-- Name: extensions; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE extensions FROM PUBLIC;
REVOKE ALL ON TABLE extensions FROM breakpad_rw;
GRANT ALL ON TABLE extensions TO breakpad_rw;
GRANT SELECT ON TABLE extensions TO monitoring;
GRANT SELECT ON TABLE extensions TO breakpad_ro;
GRANT SELECT ON TABLE extensions TO breakpad;
GRANT SELECT ON TABLE extensions TO analyst;


--
-- TOC entry 4699 (class 0 OID 0)
-- Dependencies: 787
-- Name: flash_versions; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE flash_versions FROM PUBLIC;
REVOKE ALL ON TABLE flash_versions FROM breakpad_rw;
GRANT ALL ON TABLE flash_versions TO breakpad_rw;
GRANT SELECT ON TABLE flash_versions TO breakpad_ro;
GRANT SELECT ON TABLE flash_versions TO breakpad;
GRANT ALL ON TABLE flash_versions TO monitor;
GRANT SELECT ON TABLE flash_versions TO analyst;


--
-- TOC entry 4701 (class 0 OID 0)
-- Dependencies: 734
-- Name: signatures; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE signatures FROM PUBLIC;
REVOKE ALL ON TABLE signatures FROM breakpad_rw;
GRANT ALL ON TABLE signatures TO breakpad_rw;
GRANT SELECT ON TABLE signatures TO breakpad_ro;
GRANT SELECT ON TABLE signatures TO breakpad;
GRANT ALL ON TABLE signatures TO monitor;
GRANT SELECT ON TABLE signatures TO analyst;


--
-- TOC entry 4702 (class 0 OID 0)
-- Dependencies: 797
-- Name: hang_report; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE hang_report FROM PUBLIC;
REVOKE ALL ON TABLE hang_report FROM breakpad_rw;
GRANT ALL ON TABLE hang_report TO breakpad_rw;
GRANT SELECT ON TABLE hang_report TO breakpad_ro;
GRANT SELECT ON TABLE hang_report TO breakpad;
GRANT ALL ON TABLE hang_report TO monitor;


--
-- TOC entry 4703 (class 0 OID 0)
-- Dependencies: 878
-- Name: high_load_temp; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE high_load_temp FROM PUBLIC;
REVOKE ALL ON TABLE high_load_temp FROM postgres;
GRANT ALL ON TABLE high_load_temp TO postgres;
GRANT SELECT ON TABLE high_load_temp TO breakpad_ro;
GRANT SELECT ON TABLE high_load_temp TO breakpad;
GRANT ALL ON TABLE high_load_temp TO monitor;


--
-- TOC entry 4704 (class 0 OID 0)
-- Dependencies: 627
-- Name: jobs; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE jobs FROM PUBLIC;
REVOKE ALL ON TABLE jobs FROM breakpad_rw;
GRANT ALL ON TABLE jobs TO breakpad_rw;
GRANT SELECT ON TABLE jobs TO monitoring;
GRANT SELECT ON TABLE jobs TO breakpad_ro;
GRANT SELECT ON TABLE jobs TO breakpad;
GRANT SELECT ON TABLE jobs TO analyst;


--
-- TOC entry 4706 (class 0 OID 0)
-- Dependencies: 628
-- Name: jobs_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE jobs_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE jobs_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE jobs_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE jobs_id_seq TO breakpad;


--
-- TOC entry 4707 (class 0 OID 0)
-- Dependencies: 632
-- Name: jobs_in_queue; Type: ACL; Schema: public; Owner: monitoring
--

REVOKE ALL ON TABLE jobs_in_queue FROM PUBLIC;
REVOKE ALL ON TABLE jobs_in_queue FROM monitoring;
GRANT ALL ON TABLE jobs_in_queue TO monitoring;
GRANT SELECT ON TABLE jobs_in_queue TO breakpad_ro;
GRANT SELECT ON TABLE jobs_in_queue TO breakpad;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE jobs_in_queue TO breakpad_rw;


--
-- TOC entry 4708 (class 0 OID 0)
-- Dependencies: 921
-- Name: nightly_builds; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE nightly_builds FROM PUBLIC;
REVOKE ALL ON TABLE nightly_builds FROM breakpad_rw;
GRANT ALL ON TABLE nightly_builds TO breakpad_rw;
GRANT SELECT ON TABLE nightly_builds TO breakpad_ro;
GRANT SELECT ON TABLE nightly_builds TO breakpad;
GRANT ALL ON TABLE nightly_builds TO monitor;


--
-- TOC entry 4709 (class 0 OID 0)
-- Dependencies: 744
-- Name: os_name_matches; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE os_name_matches FROM PUBLIC;
REVOKE ALL ON TABLE os_name_matches FROM breakpad_rw;
GRANT ALL ON TABLE os_name_matches TO breakpad_rw;
GRANT SELECT ON TABLE os_name_matches TO breakpad_ro;
GRANT SELECT ON TABLE os_name_matches TO breakpad;
GRANT ALL ON TABLE os_name_matches TO monitor;


--
-- TOC entry 4710 (class 0 OID 0)
-- Dependencies: 741
-- Name: os_names; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE os_names FROM PUBLIC;
REVOKE ALL ON TABLE os_names FROM breakpad_rw;
GRANT ALL ON TABLE os_names TO breakpad_rw;
GRANT SELECT ON TABLE os_names TO breakpad_ro;
GRANT SELECT ON TABLE os_names TO breakpad;
GRANT ALL ON TABLE os_names TO monitor;
GRANT SELECT ON TABLE os_names TO analyst;


--
-- TOC entry 4711 (class 0 OID 0)
-- Dependencies: 743
-- Name: os_versions; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE os_versions FROM PUBLIC;
REVOKE ALL ON TABLE os_versions FROM breakpad_rw;
GRANT ALL ON TABLE os_versions TO breakpad_rw;
GRANT SELECT ON TABLE os_versions TO breakpad_ro;
GRANT SELECT ON TABLE os_versions TO breakpad;
GRANT ALL ON TABLE os_versions TO monitor;
GRANT SELECT ON TABLE os_versions TO analyst;


--
-- TOC entry 4713 (class 0 OID 0)
-- Dependencies: 742
-- Name: os_versions_os_version_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE os_versions_os_version_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE os_versions_os_version_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE os_versions_os_version_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE os_versions_os_version_id_seq TO breakpad;


--
-- TOC entry 4714 (class 0 OID 0)
-- Dependencies: 583
-- Name: osdims; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE osdims FROM PUBLIC;
REVOKE ALL ON TABLE osdims FROM breakpad_rw;
GRANT ALL ON TABLE osdims TO breakpad_rw;
GRANT SELECT ON TABLE osdims TO monitoring;
GRANT SELECT ON TABLE osdims TO breakpad_ro;
GRANT SELECT ON TABLE osdims TO breakpad;


--
-- TOC entry 4716 (class 0 OID 0)
-- Dependencies: 584
-- Name: osdims_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE osdims_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE osdims_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE osdims_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE osdims_id_seq TO breakpad;


--
-- TOC entry 4717 (class 0 OID 0)
-- Dependencies: 620
-- Name: top_crashes_by_signature; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE top_crashes_by_signature FROM PUBLIC;
REVOKE ALL ON TABLE top_crashes_by_signature FROM breakpad_rw;
GRANT ALL ON TABLE top_crashes_by_signature TO breakpad_rw;
GRANT SELECT ON TABLE top_crashes_by_signature TO monitoring;
GRANT SELECT ON TABLE top_crashes_by_signature TO breakpad_ro;
GRANT SELECT ON TABLE top_crashes_by_signature TO breakpad;


--
-- TOC entry 4718 (class 0 OID 0)
-- Dependencies: 676
-- Name: performance_check_1; Type: ACL; Schema: public; Owner: monitoring
--

REVOKE ALL ON TABLE performance_check_1 FROM PUBLIC;
REVOKE ALL ON TABLE performance_check_1 FROM monitoring;
GRANT ALL ON TABLE performance_check_1 TO monitoring;
GRANT SELECT ON TABLE performance_check_1 TO breakpad_ro;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE performance_check_1 TO breakpad_rw;
GRANT SELECT ON TABLE performance_check_1 TO breakpad;


--
-- TOC entry 4719 (class 0 OID 0)
-- Dependencies: 657
-- Name: pg_stat_statements; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE pg_stat_statements FROM PUBLIC;
REVOKE ALL ON TABLE pg_stat_statements FROM postgres;
GRANT ALL ON TABLE pg_stat_statements TO postgres;
GRANT SELECT ON TABLE pg_stat_statements TO PUBLIC;
GRANT SELECT ON TABLE pg_stat_statements TO breakpad_ro;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE pg_stat_statements TO breakpad_rw;
GRANT SELECT ON TABLE pg_stat_statements TO breakpad;


--
-- TOC entry 4720 (class 0 OID 0)
-- Dependencies: 585
-- Name: plugins; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE plugins FROM PUBLIC;
REVOKE ALL ON TABLE plugins FROM breakpad_rw;
GRANT ALL ON TABLE plugins TO breakpad_rw;
GRANT SELECT ON TABLE plugins TO monitoring;
GRANT SELECT ON TABLE plugins TO breakpad_ro;
GRANT SELECT ON TABLE plugins TO breakpad;
GRANT SELECT ON TABLE plugins TO analyst;


--
-- TOC entry 4722 (class 0 OID 0)
-- Dependencies: 586
-- Name: plugins_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE plugins_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE plugins_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE plugins_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE plugins_id_seq TO breakpad;


--
-- TOC entry 4723 (class 0 OID 0)
-- Dependencies: 587
-- Name: plugins_reports; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE plugins_reports FROM PUBLIC;
REVOKE ALL ON TABLE plugins_reports FROM breakpad_rw;
GRANT ALL ON TABLE plugins_reports TO breakpad_rw;
GRANT SELECT ON TABLE plugins_reports TO monitoring;
GRANT SELECT ON TABLE plugins_reports TO breakpad_ro;
GRANT SELECT ON TABLE plugins_reports TO breakpad;
GRANT SELECT ON TABLE plugins_reports TO analyst;


--
-- TOC entry 4724 (class 0 OID 0)
-- Dependencies: 852
-- Name: priority_jobs_1956; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_1956 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_1956 FROM processor;
GRANT ALL ON TABLE priority_jobs_1956 TO processor;
GRANT ALL ON TABLE priority_jobs_1956 TO breakpad_rw;


--
-- TOC entry 4725 (class 0 OID 0)
-- Dependencies: 855
-- Name: priority_jobs_2034; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2034 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2034 FROM processor;
GRANT ALL ON TABLE priority_jobs_2034 TO processor;
GRANT ALL ON TABLE priority_jobs_2034 TO breakpad_rw;


--
-- TOC entry 4726 (class 0 OID 0)
-- Dependencies: 910
-- Name: priority_jobs_2276; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2276 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2276 FROM processor;
GRANT ALL ON TABLE priority_jobs_2276 TO processor;
GRANT ALL ON TABLE priority_jobs_2276 TO breakpad_rw;


--
-- TOC entry 4727 (class 0 OID 0)
-- Dependencies: 955
-- Name: priority_jobs_2510; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2510 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2510 FROM processor;
GRANT ALL ON TABLE priority_jobs_2510 TO processor;
GRANT ALL ON TABLE priority_jobs_2510 TO breakpad_rw;


--
-- TOC entry 4728 (class 0 OID 0)
-- Dependencies: 956
-- Name: priority_jobs_2511; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2511 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2511 FROM processor;
GRANT ALL ON TABLE priority_jobs_2511 TO processor;
GRANT ALL ON TABLE priority_jobs_2511 TO breakpad_rw;


--
-- TOC entry 4729 (class 0 OID 0)
-- Dependencies: 957
-- Name: priority_jobs_2512; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2512 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2512 FROM processor;
GRANT ALL ON TABLE priority_jobs_2512 TO processor;
GRANT ALL ON TABLE priority_jobs_2512 TO breakpad_rw;


--
-- TOC entry 4730 (class 0 OID 0)
-- Dependencies: 958
-- Name: priority_jobs_2513; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2513 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2513 FROM processor;
GRANT ALL ON TABLE priority_jobs_2513 TO processor;
GRANT ALL ON TABLE priority_jobs_2513 TO breakpad_rw;


--
-- TOC entry 4731 (class 0 OID 0)
-- Dependencies: 959
-- Name: priority_jobs_2514; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2514 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2514 FROM processor;
GRANT ALL ON TABLE priority_jobs_2514 TO processor;
GRANT ALL ON TABLE priority_jobs_2514 TO breakpad_rw;


--
-- TOC entry 4732 (class 0 OID 0)
-- Dependencies: 960
-- Name: priority_jobs_2515; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2515 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2515 FROM processor;
GRANT ALL ON TABLE priority_jobs_2515 TO processor;
GRANT ALL ON TABLE priority_jobs_2515 TO breakpad_rw;


--
-- TOC entry 4733 (class 0 OID 0)
-- Dependencies: 961
-- Name: priority_jobs_2516; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2516 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2516 FROM processor;
GRANT ALL ON TABLE priority_jobs_2516 TO processor;
GRANT ALL ON TABLE priority_jobs_2516 TO breakpad_rw;


--
-- TOC entry 4734 (class 0 OID 0)
-- Dependencies: 962
-- Name: priority_jobs_2517; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2517 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2517 FROM processor;
GRANT ALL ON TABLE priority_jobs_2517 TO processor;
GRANT ALL ON TABLE priority_jobs_2517 TO breakpad_rw;


--
-- TOC entry 4735 (class 0 OID 0)
-- Dependencies: 963
-- Name: priority_jobs_2518; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2518 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2518 FROM processor;
GRANT ALL ON TABLE priority_jobs_2518 TO processor;
GRANT ALL ON TABLE priority_jobs_2518 TO breakpad_rw;


--
-- TOC entry 4736 (class 0 OID 0)
-- Dependencies: 964
-- Name: priority_jobs_2519; Type: ACL; Schema: public; Owner: processor
--

REVOKE ALL ON TABLE priority_jobs_2519 FROM PUBLIC;
REVOKE ALL ON TABLE priority_jobs_2519 FROM processor;
GRANT ALL ON TABLE priority_jobs_2519 TO processor;
GRANT ALL ON TABLE priority_jobs_2519 TO breakpad_rw;


--
-- TOC entry 4737 (class 0 OID 0)
-- Dependencies: 629
-- Name: priorityjobs; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE priorityjobs FROM PUBLIC;
REVOKE ALL ON TABLE priorityjobs FROM breakpad_rw;
GRANT ALL ON TABLE priorityjobs TO breakpad_rw;
GRANT SELECT ON TABLE priorityjobs TO monitoring;
GRANT SELECT ON TABLE priorityjobs TO breakpad_ro;
GRANT SELECT ON TABLE priorityjobs TO breakpad;


--
-- TOC entry 4738 (class 0 OID 0)
-- Dependencies: 630
-- Name: priorityjobs_log; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE priorityjobs_log FROM PUBLIC;
REVOKE ALL ON TABLE priorityjobs_log FROM postgres;
GRANT ALL ON TABLE priorityjobs_log TO postgres;
GRANT SELECT ON TABLE priorityjobs_log TO monitoring;
GRANT SELECT ON TABLE priorityjobs_log TO breakpad_ro;
GRANT ALL ON TABLE priorityjobs_log TO breakpad;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE priorityjobs_log TO breakpad_rw;


--
-- TOC entry 4739 (class 0 OID 0)
-- Dependencies: 631
-- Name: priorityjobs_logging_switch; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE priorityjobs_logging_switch FROM PUBLIC;
REVOKE ALL ON TABLE priorityjobs_logging_switch FROM postgres;
GRANT ALL ON TABLE priorityjobs_logging_switch TO postgres;
GRANT SELECT ON TABLE priorityjobs_logging_switch TO monitoring;
GRANT SELECT ON TABLE priorityjobs_logging_switch TO breakpad_ro;
GRANT SELECT ON TABLE priorityjobs_logging_switch TO breakpad;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE priorityjobs_logging_switch TO breakpad_rw;


--
-- TOC entry 4740 (class 0 OID 0)
-- Dependencies: 792
-- Name: process_types; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE process_types FROM PUBLIC;
REVOKE ALL ON TABLE process_types FROM breakpad_rw;
GRANT ALL ON TABLE process_types TO breakpad_rw;
GRANT SELECT ON TABLE process_types TO breakpad_ro;
GRANT SELECT ON TABLE process_types TO breakpad;
GRANT ALL ON TABLE process_types TO monitor;
GRANT SELECT ON TABLE process_types TO analyst;


--
-- TOC entry 4741 (class 0 OID 0)
-- Dependencies: 599
-- Name: processors; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE processors FROM PUBLIC;
REVOKE ALL ON TABLE processors FROM breakpad_rw;
GRANT ALL ON TABLE processors TO breakpad_rw;
GRANT SELECT ON TABLE processors TO monitoring;
GRANT SELECT ON TABLE processors TO breakpad_ro;
GRANT SELECT ON TABLE processors TO breakpad;


--
-- TOC entry 4743 (class 0 OID 0)
-- Dependencies: 600
-- Name: processors_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE processors_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE processors_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE processors_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE processors_id_seq TO breakpad;


--
-- TOC entry 4744 (class 0 OID 0)
-- Dependencies: 745
-- Name: product_adu; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_adu FROM PUBLIC;
REVOKE ALL ON TABLE product_adu FROM breakpad_rw;
GRANT ALL ON TABLE product_adu TO breakpad_rw;
GRANT SELECT ON TABLE product_adu TO breakpad_ro;
GRANT SELECT ON TABLE product_adu TO breakpad;
GRANT ALL ON TABLE product_adu TO monitor;
GRANT SELECT ON TABLE product_adu TO analyst;


--
-- TOC entry 4745 (class 0 OID 0)
-- Dependencies: 739
-- Name: product_release_channels; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_release_channels FROM PUBLIC;
REVOKE ALL ON TABLE product_release_channels FROM breakpad_rw;
GRANT ALL ON TABLE product_release_channels TO breakpad_rw;
GRANT SELECT ON TABLE product_release_channels TO breakpad_ro;
GRANT SELECT ON TABLE product_release_channels TO breakpad;
GRANT ALL ON TABLE product_release_channels TO monitor;
GRANT SELECT ON TABLE product_release_channels TO analyst;


--
-- TOC entry 4746 (class 0 OID 0)
-- Dependencies: 934
-- Name: product_crash_ratio; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_crash_ratio FROM PUBLIC;
REVOKE ALL ON TABLE product_crash_ratio FROM breakpad_rw;
GRANT ALL ON TABLE product_crash_ratio TO breakpad_rw;
GRANT SELECT ON TABLE product_crash_ratio TO breakpad_ro;
GRANT SELECT ON TABLE product_crash_ratio TO breakpad;
GRANT ALL ON TABLE product_crash_ratio TO monitor;
GRANT SELECT ON TABLE product_crash_ratio TO analyst;


--
-- TOC entry 4747 (class 0 OID 0)
-- Dependencies: 601
-- Name: product_visibility; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_visibility FROM PUBLIC;
REVOKE ALL ON TABLE product_visibility FROM breakpad_rw;
GRANT ALL ON TABLE product_visibility TO breakpad_rw;
GRANT SELECT ON TABLE product_visibility TO monitoring;
GRANT SELECT ON TABLE product_visibility TO breakpad_ro;
GRANT SELECT ON TABLE product_visibility TO breakpad;


--
-- TOC entry 4748 (class 0 OID 0)
-- Dependencies: 732
-- Name: release_build_type_map; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE release_build_type_map FROM PUBLIC;
REVOKE ALL ON TABLE release_build_type_map FROM breakpad_rw;
GRANT ALL ON TABLE release_build_type_map TO breakpad_rw;
GRANT SELECT ON TABLE release_build_type_map TO breakpad_ro;
GRANT SELECT ON TABLE release_build_type_map TO breakpad;
GRANT ALL ON TABLE release_build_type_map TO monitor;


--
-- TOC entry 4749 (class 0 OID 0)
-- Dependencies: 844
-- Name: product_info; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_info FROM PUBLIC;
REVOKE ALL ON TABLE product_info FROM breakpad_rw;
GRANT ALL ON TABLE product_info TO breakpad_rw;
GRANT SELECT ON TABLE product_info TO breakpad_ro;
GRANT SELECT ON TABLE product_info TO breakpad;
GRANT ALL ON TABLE product_info TO monitor;


--
-- TOC entry 4750 (class 0 OID 0)
-- Dependencies: 846
-- Name: product_info_changelog; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_info_changelog FROM PUBLIC;
REVOKE ALL ON TABLE product_info_changelog FROM breakpad_rw;
GRANT ALL ON TABLE product_info_changelog TO breakpad_rw;
GRANT SELECT ON TABLE product_info_changelog TO breakpad_ro;
GRANT SELECT ON TABLE product_info_changelog TO breakpad;
GRANT ALL ON TABLE product_info_changelog TO monitor;


--
-- TOC entry 4751 (class 0 OID 0)
-- Dependencies: 935
-- Name: product_os_crash_ratio; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_os_crash_ratio FROM PUBLIC;
REVOKE ALL ON TABLE product_os_crash_ratio FROM breakpad_rw;
GRANT ALL ON TABLE product_os_crash_ratio TO breakpad_rw;
GRANT SELECT ON TABLE product_os_crash_ratio TO breakpad_ro;
GRANT SELECT ON TABLE product_os_crash_ratio TO breakpad;
GRANT ALL ON TABLE product_os_crash_ratio TO monitor;
GRANT SELECT ON TABLE product_os_crash_ratio TO analyst;


--
-- TOC entry 4752 (class 0 OID 0)
-- Dependencies: 860
-- Name: product_productid_map; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_productid_map FROM PUBLIC;
REVOKE ALL ON TABLE product_productid_map FROM breakpad_rw;
GRANT ALL ON TABLE product_productid_map TO breakpad_rw;
GRANT SELECT ON TABLE product_productid_map TO breakpad_ro;
GRANT SELECT ON TABLE product_productid_map TO breakpad;
GRANT ALL ON TABLE product_productid_map TO monitor;
GRANT SELECT ON TABLE product_productid_map TO analyst;


--
-- TOC entry 4753 (class 0 OID 0)
-- Dependencies: 843
-- Name: product_selector; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_selector FROM PUBLIC;
REVOKE ALL ON TABLE product_selector FROM breakpad_rw;
GRANT ALL ON TABLE product_selector TO breakpad_rw;
GRANT SELECT ON TABLE product_selector TO breakpad_ro;
GRANT SELECT ON TABLE product_selector TO breakpad;
GRANT ALL ON TABLE product_selector TO monitor;


--
-- TOC entry 4754 (class 0 OID 0)
-- Dependencies: 731
-- Name: product_version_builds; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE product_version_builds FROM PUBLIC;
REVOKE ALL ON TABLE product_version_builds FROM breakpad_rw;
GRANT ALL ON TABLE product_version_builds TO breakpad_rw;
GRANT SELECT ON TABLE product_version_builds TO breakpad_ro;
GRANT SELECT ON TABLE product_version_builds TO breakpad;
GRANT ALL ON TABLE product_version_builds TO monitor;
GRANT SELECT ON TABLE product_version_builds TO analyst;


--
-- TOC entry 4755 (class 0 OID 0)
-- Dependencies: 678
-- Name: productdims_version_sort; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE productdims_version_sort FROM PUBLIC;
REVOKE ALL ON TABLE productdims_version_sort FROM breakpad_rw;
GRANT ALL ON TABLE productdims_version_sort TO breakpad_rw;
GRANT SELECT ON TABLE productdims_version_sort TO breakpad_ro;
GRANT SELECT ON TABLE productdims_version_sort TO breakpad;


--
-- TOC entry 4756 (class 0 OID 0)
-- Dependencies: 728
-- Name: products; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE products FROM PUBLIC;
REVOKE ALL ON TABLE products FROM breakpad_rw;
GRANT ALL ON TABLE products TO breakpad_rw;
GRANT SELECT ON TABLE products TO breakpad_ro;
GRANT SELECT ON TABLE products TO breakpad;
GRANT ALL ON TABLE products TO monitor;
GRANT SELECT ON TABLE products TO analyst;


--
-- TOC entry 4757 (class 0 OID 0)
-- Dependencies: 893
-- Name: rank_compare; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE rank_compare FROM PUBLIC;
REVOKE ALL ON TABLE rank_compare FROM breakpad_rw;
GRANT ALL ON TABLE rank_compare TO breakpad_rw;
GRANT SELECT ON TABLE rank_compare TO breakpad_ro;
GRANT SELECT ON TABLE rank_compare TO breakpad;
GRANT ALL ON TABLE rank_compare TO monitor;
GRANT SELECT ON TABLE rank_compare TO analyst;


--
-- TOC entry 4758 (class 0 OID 0)
-- Dependencies: 603
-- Name: raw_adu; Type: ACL; Schema: public; Owner: breakpad_metrics
--

REVOKE ALL ON TABLE raw_adu FROM PUBLIC;
REVOKE ALL ON TABLE raw_adu FROM breakpad_metrics;
GRANT ALL ON TABLE raw_adu TO breakpad_metrics;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE raw_adu TO breakpad_rw;
GRANT SELECT ON TABLE raw_adu TO nagiosdaemon;
GRANT SELECT ON TABLE raw_adu TO monitoring;
GRANT SELECT ON TABLE raw_adu TO breakpad_ro;
GRANT SELECT ON TABLE raw_adu TO breakpad;
GRANT SELECT ON TABLE raw_adu TO analyst;


--
-- TOC entry 4759 (class 0 OID 0)
-- Dependencies: 785
-- Name: reasons; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE reasons FROM PUBLIC;
REVOKE ALL ON TABLE reasons FROM breakpad_rw;
GRANT ALL ON TABLE reasons TO breakpad_rw;
GRANT SELECT ON TABLE reasons TO breakpad_ro;
GRANT SELECT ON TABLE reasons TO breakpad;
GRANT ALL ON TABLE reasons TO monitor;
GRANT SELECT ON TABLE reasons TO analyst;


--
-- TOC entry 4761 (class 0 OID 0)
-- Dependencies: 740
-- Name: release_channel_matches; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE release_channel_matches FROM PUBLIC;
REVOKE ALL ON TABLE release_channel_matches FROM breakpad_rw;
GRANT ALL ON TABLE release_channel_matches TO breakpad_rw;
GRANT SELECT ON TABLE release_channel_matches TO breakpad_ro;
GRANT SELECT ON TABLE release_channel_matches TO breakpad;
GRANT ALL ON TABLE release_channel_matches TO monitor;


--
-- TOC entry 4762 (class 0 OID 0)
-- Dependencies: 729
-- Name: release_channels; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE release_channels FROM PUBLIC;
REVOKE ALL ON TABLE release_channels FROM breakpad_rw;
GRANT ALL ON TABLE release_channels TO breakpad_rw;
GRANT SELECT ON TABLE release_channels TO breakpad_ro;
GRANT SELECT ON TABLE release_channels TO breakpad;
GRANT ALL ON TABLE release_channels TO monitor;
GRANT SELECT ON TABLE release_channels TO analyst;


--
-- TOC entry 4763 (class 0 OID 0)
-- Dependencies: 727
-- Name: releases_raw; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE releases_raw FROM PUBLIC;
REVOKE ALL ON TABLE releases_raw FROM breakpad_rw;
GRANT ALL ON TABLE releases_raw TO breakpad_rw;
GRANT SELECT ON TABLE releases_raw TO breakpad_ro;
GRANT SELECT ON TABLE releases_raw TO breakpad;
GRANT ALL ON TABLE releases_raw TO monitor;
GRANT SELECT ON TABLE releases_raw TO analyst;


--
-- TOC entry 4764 (class 0 OID 0)
-- Dependencies: 633
-- Name: replication_test; Type: ACL; Schema: public; Owner: monitoring
--

REVOKE ALL ON TABLE replication_test FROM PUBLIC;
REVOKE ALL ON TABLE replication_test FROM monitoring;
GRANT ALL ON TABLE replication_test TO monitoring;
GRANT SELECT ON TABLE replication_test TO breakpad;
GRANT SELECT ON TABLE replication_test TO breakpad_ro;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE replication_test TO breakpad_rw;


--
-- TOC entry 4765 (class 0 OID 0)
-- Dependencies: 834
-- Name: report_partition_info; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE report_partition_info FROM PUBLIC;
REVOKE ALL ON TABLE report_partition_info FROM breakpad_rw;
GRANT ALL ON TABLE report_partition_info TO breakpad_rw;
GRANT SELECT ON TABLE report_partition_info TO breakpad_ro;
GRANT SELECT ON TABLE report_partition_info TO breakpad;
GRANT ALL ON TABLE report_partition_info TO monitor;


--
-- TOC entry 4766 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE reports FROM PUBLIC;
REVOKE ALL ON TABLE reports FROM breakpad_rw;
GRANT ALL ON TABLE reports TO breakpad_rw;
GRANT SELECT ON TABLE reports TO monitoring;
GRANT SELECT ON TABLE reports TO breakpad_ro;
GRANT SELECT ON TABLE reports TO breakpad;


--
-- TOC entry 4767 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.id; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(id) ON TABLE reports FROM PUBLIC;
REVOKE ALL(id) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(id) ON TABLE reports TO analyst;


--
-- TOC entry 4768 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.client_crash_date; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(client_crash_date) ON TABLE reports FROM PUBLIC;
REVOKE ALL(client_crash_date) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(client_crash_date) ON TABLE reports TO analyst;


--
-- TOC entry 4769 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.date_processed; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(date_processed) ON TABLE reports FROM PUBLIC;
REVOKE ALL(date_processed) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(date_processed) ON TABLE reports TO analyst;


--
-- TOC entry 4770 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.uuid; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(uuid) ON TABLE reports FROM PUBLIC;
REVOKE ALL(uuid) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(uuid) ON TABLE reports TO analyst;


--
-- TOC entry 4771 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.product; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(product) ON TABLE reports FROM PUBLIC;
REVOKE ALL(product) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(product) ON TABLE reports TO analyst;


--
-- TOC entry 4772 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.version; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(version) ON TABLE reports FROM PUBLIC;
REVOKE ALL(version) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(version) ON TABLE reports TO analyst;


--
-- TOC entry 4773 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.build; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(build) ON TABLE reports FROM PUBLIC;
REVOKE ALL(build) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(build) ON TABLE reports TO analyst;


--
-- TOC entry 4774 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.signature; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(signature) ON TABLE reports FROM PUBLIC;
REVOKE ALL(signature) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(signature) ON TABLE reports TO analyst;


--
-- TOC entry 4775 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.install_age; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(install_age) ON TABLE reports FROM PUBLIC;
REVOKE ALL(install_age) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(install_age) ON TABLE reports TO analyst;


--
-- TOC entry 4776 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.last_crash; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(last_crash) ON TABLE reports FROM PUBLIC;
REVOKE ALL(last_crash) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(last_crash) ON TABLE reports TO analyst;


--
-- TOC entry 4777 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.uptime; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(uptime) ON TABLE reports FROM PUBLIC;
REVOKE ALL(uptime) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(uptime) ON TABLE reports TO analyst;


--
-- TOC entry 4778 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.cpu_name; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(cpu_name) ON TABLE reports FROM PUBLIC;
REVOKE ALL(cpu_name) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(cpu_name) ON TABLE reports TO analyst;


--
-- TOC entry 4779 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.cpu_info; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(cpu_info) ON TABLE reports FROM PUBLIC;
REVOKE ALL(cpu_info) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(cpu_info) ON TABLE reports TO analyst;


--
-- TOC entry 4780 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.reason; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(reason) ON TABLE reports FROM PUBLIC;
REVOKE ALL(reason) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(reason) ON TABLE reports TO analyst;


--
-- TOC entry 4781 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.address; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(address) ON TABLE reports FROM PUBLIC;
REVOKE ALL(address) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(address) ON TABLE reports TO analyst;


--
-- TOC entry 4782 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.os_name; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(os_name) ON TABLE reports FROM PUBLIC;
REVOKE ALL(os_name) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(os_name) ON TABLE reports TO analyst;


--
-- TOC entry 4783 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.os_version; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(os_version) ON TABLE reports FROM PUBLIC;
REVOKE ALL(os_version) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(os_version) ON TABLE reports TO analyst;


--
-- TOC entry 4784 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.user_id; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(user_id) ON TABLE reports FROM PUBLIC;
REVOKE ALL(user_id) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(user_id) ON TABLE reports TO analyst;


--
-- TOC entry 4785 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.started_datetime; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(started_datetime) ON TABLE reports FROM PUBLIC;
REVOKE ALL(started_datetime) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(started_datetime) ON TABLE reports TO analyst;


--
-- TOC entry 4786 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.completed_datetime; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(completed_datetime) ON TABLE reports FROM PUBLIC;
REVOKE ALL(completed_datetime) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(completed_datetime) ON TABLE reports TO analyst;


--
-- TOC entry 4787 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.success; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(success) ON TABLE reports FROM PUBLIC;
REVOKE ALL(success) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(success) ON TABLE reports TO analyst;


--
-- TOC entry 4788 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.truncated; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(truncated) ON TABLE reports FROM PUBLIC;
REVOKE ALL(truncated) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(truncated) ON TABLE reports TO analyst;


--
-- TOC entry 4789 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.processor_notes; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(processor_notes) ON TABLE reports FROM PUBLIC;
REVOKE ALL(processor_notes) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(processor_notes) ON TABLE reports TO analyst;


--
-- TOC entry 4790 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.user_comments; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(user_comments) ON TABLE reports FROM PUBLIC;
REVOKE ALL(user_comments) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(user_comments) ON TABLE reports TO analyst;


--
-- TOC entry 4791 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.app_notes; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(app_notes) ON TABLE reports FROM PUBLIC;
REVOKE ALL(app_notes) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(app_notes) ON TABLE reports TO analyst;


--
-- TOC entry 4792 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.distributor; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(distributor) ON TABLE reports FROM PUBLIC;
REVOKE ALL(distributor) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(distributor) ON TABLE reports TO analyst;


--
-- TOC entry 4793 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.distributor_version; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(distributor_version) ON TABLE reports FROM PUBLIC;
REVOKE ALL(distributor_version) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(distributor_version) ON TABLE reports TO analyst;


--
-- TOC entry 4794 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.topmost_filenames; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(topmost_filenames) ON TABLE reports FROM PUBLIC;
REVOKE ALL(topmost_filenames) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(topmost_filenames) ON TABLE reports TO analyst;


--
-- TOC entry 4795 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.addons_checked; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(addons_checked) ON TABLE reports FROM PUBLIC;
REVOKE ALL(addons_checked) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(addons_checked) ON TABLE reports TO analyst;


--
-- TOC entry 4796 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.flash_version; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(flash_version) ON TABLE reports FROM PUBLIC;
REVOKE ALL(flash_version) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(flash_version) ON TABLE reports TO analyst;


--
-- TOC entry 4797 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.hangid; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(hangid) ON TABLE reports FROM PUBLIC;
REVOKE ALL(hangid) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(hangid) ON TABLE reports TO analyst;


--
-- TOC entry 4798 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.process_type; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(process_type) ON TABLE reports FROM PUBLIC;
REVOKE ALL(process_type) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(process_type) ON TABLE reports TO analyst;


--
-- TOC entry 4799 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.release_channel; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(release_channel) ON TABLE reports FROM PUBLIC;
REVOKE ALL(release_channel) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(release_channel) ON TABLE reports TO analyst;


--
-- TOC entry 4800 (class 0 OID 0)
-- Dependencies: 604
-- Name: reports.productid; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(productid) ON TABLE reports FROM PUBLIC;
REVOKE ALL(productid) ON TABLE reports FROM breakpad_rw;
GRANT SELECT(productid) ON TABLE reports TO analyst;


--
-- TOC entry 4801 (class 0 OID 0)
-- Dependencies: 795
-- Name: reports_bad; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE reports_bad FROM PUBLIC;
REVOKE ALL ON TABLE reports_bad FROM breakpad_rw;
GRANT ALL ON TABLE reports_bad TO breakpad_rw;
GRANT SELECT ON TABLE reports_bad TO breakpad_ro;
GRANT SELECT ON TABLE reports_bad TO breakpad;
GRANT ALL ON TABLE reports_bad TO monitor;
GRANT SELECT ON TABLE reports_bad TO analyst;


--
-- TOC entry 4802 (class 0 OID 0)
-- Dependencies: 793
-- Name: reports_clean; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE reports_clean FROM PUBLIC;
REVOKE ALL ON TABLE reports_clean FROM breakpad_rw;
GRANT ALL ON TABLE reports_clean TO breakpad_rw;
GRANT SELECT ON TABLE reports_clean TO breakpad_ro;
GRANT SELECT ON TABLE reports_clean TO breakpad;
GRANT ALL ON TABLE reports_clean TO monitor;
GRANT SELECT ON TABLE reports_clean TO analyst;


--
-- TOC entry 4803 (class 0 OID 0)
-- Dependencies: 672
-- Name: reports_duplicates; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE reports_duplicates FROM PUBLIC;
REVOKE ALL ON TABLE reports_duplicates FROM breakpad_rw;
GRANT ALL ON TABLE reports_duplicates TO breakpad_rw;
GRANT SELECT ON TABLE reports_duplicates TO breakpad_ro;
GRANT SELECT ON TABLE reports_duplicates TO breakpad;
GRANT SELECT ON TABLE reports_duplicates TO analyst;


--
-- TOC entry 4805 (class 0 OID 0)
-- Dependencies: 605
-- Name: reports_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE reports_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE reports_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE reports_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE reports_id_seq TO breakpad;


--
-- TOC entry 4806 (class 0 OID 0)
-- Dependencies: 794
-- Name: reports_user_info; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE reports_user_info FROM PUBLIC;
REVOKE ALL ON TABLE reports_user_info FROM breakpad_rw;
GRANT ALL ON TABLE reports_user_info TO breakpad_rw;
GRANT SELECT ON TABLE reports_user_info TO breakpad_ro;
GRANT SELECT ON TABLE reports_user_info TO breakpad;
GRANT ALL ON TABLE reports_user_info TO monitor;


--
-- TOC entry 4807 (class 0 OID 0)
-- Dependencies: 794
-- Name: reports_user_info.uuid; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(uuid) ON TABLE reports_user_info FROM PUBLIC;
REVOKE ALL(uuid) ON TABLE reports_user_info FROM breakpad_rw;
GRANT SELECT(uuid) ON TABLE reports_user_info TO analyst;


--
-- TOC entry 4808 (class 0 OID 0)
-- Dependencies: 794
-- Name: reports_user_info.date_processed; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(date_processed) ON TABLE reports_user_info FROM PUBLIC;
REVOKE ALL(date_processed) ON TABLE reports_user_info FROM breakpad_rw;
GRANT SELECT(date_processed) ON TABLE reports_user_info TO analyst;


--
-- TOC entry 4809 (class 0 OID 0)
-- Dependencies: 794
-- Name: reports_user_info.user_comments; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(user_comments) ON TABLE reports_user_info FROM PUBLIC;
REVOKE ALL(user_comments) ON TABLE reports_user_info FROM breakpad_rw;
GRANT SELECT(user_comments) ON TABLE reports_user_info TO analyst;


--
-- TOC entry 4810 (class 0 OID 0)
-- Dependencies: 794
-- Name: reports_user_info.app_notes; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL(app_notes) ON TABLE reports_user_info FROM PUBLIC;
REVOKE ALL(app_notes) ON TABLE reports_user_info FROM breakpad_rw;
GRANT SELECT(app_notes) ON TABLE reports_user_info TO analyst;


--
-- TOC entry 4811 (class 0 OID 0)
-- Dependencies: 617
-- Name: seq_reports_id; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE seq_reports_id FROM PUBLIC;
REVOKE ALL ON SEQUENCE seq_reports_id FROM breakpad_rw;
GRANT ALL ON SEQUENCE seq_reports_id TO breakpad_rw;
GRANT SELECT ON SEQUENCE seq_reports_id TO breakpad;


--
-- TOC entry 4812 (class 0 OID 0)
-- Dependencies: 618
-- Name: server_status; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE server_status FROM PUBLIC;
REVOKE ALL ON TABLE server_status FROM breakpad_rw;
GRANT ALL ON TABLE server_status TO breakpad_rw;
GRANT SELECT ON TABLE server_status TO monitoring;
GRANT SELECT ON TABLE server_status TO breakpad_ro;
GRANT SELECT ON TABLE server_status TO breakpad;


--
-- TOC entry 4814 (class 0 OID 0)
-- Dependencies: 619
-- Name: server_status_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE server_status_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE server_status_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE server_status_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE server_status_id_seq TO breakpad;


--
-- TOC entry 4815 (class 0 OID 0)
-- Dependencies: 660
-- Name: sessions; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE sessions FROM PUBLIC;
REVOKE ALL ON TABLE sessions FROM breakpad_rw;
GRANT ALL ON TABLE sessions TO breakpad_rw;
GRANT SELECT ON TABLE sessions TO breakpad_ro;
GRANT SELECT ON TABLE sessions TO breakpad;


--
-- TOC entry 4816 (class 0 OID 0)
-- Dependencies: 738
-- Name: signature_bugs_rollup; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE signature_bugs_rollup FROM PUBLIC;
REVOKE ALL ON TABLE signature_bugs_rollup FROM breakpad_rw;
GRANT ALL ON TABLE signature_bugs_rollup TO breakpad_rw;
GRANT SELECT ON TABLE signature_bugs_rollup TO breakpad_ro;
GRANT SELECT ON TABLE signature_bugs_rollup TO breakpad;
GRANT ALL ON TABLE signature_bugs_rollup TO monitor;
GRANT SELECT ON TABLE signature_bugs_rollup TO analyst;


--
-- TOC entry 4817 (class 0 OID 0)
-- Dependencies: 736
-- Name: signature_products; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE signature_products FROM PUBLIC;
REVOKE ALL ON TABLE signature_products FROM breakpad_rw;
GRANT ALL ON TABLE signature_products TO breakpad_rw;
GRANT SELECT ON TABLE signature_products TO breakpad_ro;
GRANT SELECT ON TABLE signature_products TO breakpad;
GRANT ALL ON TABLE signature_products TO monitor;
GRANT SELECT ON TABLE signature_products TO analyst;


--
-- TOC entry 4818 (class 0 OID 0)
-- Dependencies: 737
-- Name: signature_products_rollup; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE signature_products_rollup FROM PUBLIC;
REVOKE ALL ON TABLE signature_products_rollup FROM breakpad_rw;
GRANT ALL ON TABLE signature_products_rollup TO breakpad_rw;
GRANT SELECT ON TABLE signature_products_rollup TO breakpad_ro;
GRANT SELECT ON TABLE signature_products_rollup TO breakpad;
GRANT ALL ON TABLE signature_products_rollup TO monitor;
GRANT SELECT ON TABLE signature_products_rollup TO analyst;


--
-- TOC entry 4820 (class 0 OID 0)
-- Dependencies: 733
-- Name: signatures_signature_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE signatures_signature_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE signatures_signature_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE signatures_signature_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE signatures_signature_id_seq TO breakpad;


--
-- TOC entry 4821 (class 0 OID 0)
-- Dependencies: 858
-- Name: socorro_db_version; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE socorro_db_version FROM PUBLIC;
REVOKE ALL ON TABLE socorro_db_version FROM postgres;
GRANT ALL ON TABLE socorro_db_version TO postgres;
GRANT SELECT ON TABLE socorro_db_version TO breakpad_ro;
GRANT SELECT ON TABLE socorro_db_version TO breakpad;
GRANT ALL ON TABLE socorro_db_version TO monitor;
GRANT SELECT ON TABLE socorro_db_version TO analyst;


--
-- TOC entry 4822 (class 0 OID 0)
-- Dependencies: 859
-- Name: socorro_db_version_history; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE socorro_db_version_history FROM PUBLIC;
REVOKE ALL ON TABLE socorro_db_version_history FROM postgres;
GRANT ALL ON TABLE socorro_db_version_history TO postgres;
GRANT SELECT ON TABLE socorro_db_version_history TO breakpad_ro;
GRANT SELECT ON TABLE socorro_db_version_history TO breakpad;
GRANT ALL ON TABLE socorro_db_version_history TO monitor;


--
-- TOC entry 4823 (class 0 OID 0)
-- Dependencies: 861
-- Name: special_product_platforms; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE special_product_platforms FROM PUBLIC;
REVOKE ALL ON TABLE special_product_platforms FROM breakpad_rw;
GRANT ALL ON TABLE special_product_platforms TO breakpad_rw;
GRANT SELECT ON TABLE special_product_platforms TO breakpad_ro;
GRANT SELECT ON TABLE special_product_platforms TO breakpad;
GRANT ALL ON TABLE special_product_platforms TO monitor;
GRANT SELECT ON TABLE special_product_platforms TO analyst;


--
-- TOC entry 4824 (class 0 OID 0)
-- Dependencies: 735
-- Name: tcbs; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE tcbs FROM PUBLIC;
REVOKE ALL ON TABLE tcbs FROM breakpad_rw;
GRANT ALL ON TABLE tcbs TO breakpad_rw;
GRANT SELECT ON TABLE tcbs TO breakpad_ro;
GRANT SELECT ON TABLE tcbs TO breakpad;
GRANT ALL ON TABLE tcbs TO monitor;
GRANT SELECT ON TABLE tcbs TO analyst;


--
-- TOC entry 4826 (class 0 OID 0)
-- Dependencies: 621
-- Name: top_crashes_by_signature_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE top_crashes_by_signature_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE top_crashes_by_signature_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE top_crashes_by_signature_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE top_crashes_by_signature_id_seq TO breakpad;


--
-- TOC entry 4827 (class 0 OID 0)
-- Dependencies: 622
-- Name: top_crashes_by_url; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE top_crashes_by_url FROM PUBLIC;
REVOKE ALL ON TABLE top_crashes_by_url FROM breakpad_rw;
GRANT ALL ON TABLE top_crashes_by_url TO breakpad_rw;
GRANT SELECT ON TABLE top_crashes_by_url TO monitoring;
GRANT SELECT ON TABLE top_crashes_by_url TO breakpad_ro;
GRANT SELECT ON TABLE top_crashes_by_url TO breakpad;


--
-- TOC entry 4829 (class 0 OID 0)
-- Dependencies: 623
-- Name: top_crashes_by_url_id_seq; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE top_crashes_by_url_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE top_crashes_by_url_id_seq FROM breakpad_rw;
GRANT ALL ON SEQUENCE top_crashes_by_url_id_seq TO breakpad_rw;
GRANT SELECT ON SEQUENCE top_crashes_by_url_id_seq TO breakpad;


--
-- TOC entry 4830 (class 0 OID 0)
-- Dependencies: 624
-- Name: top_crashes_by_url_signature; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE top_crashes_by_url_signature FROM PUBLIC;
REVOKE ALL ON TABLE top_crashes_by_url_signature FROM breakpad_rw;
GRANT ALL ON TABLE top_crashes_by_url_signature TO breakpad_rw;
GRANT SELECT ON TABLE top_crashes_by_url_signature TO monitoring;
GRANT SELECT ON TABLE top_crashes_by_url_signature TO breakpad_ro;
GRANT SELECT ON TABLE top_crashes_by_url_signature TO breakpad;


--
-- TOC entry 4831 (class 0 OID 0)
-- Dependencies: 928
-- Name: transform_rules; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE transform_rules FROM PUBLIC;
REVOKE ALL ON TABLE transform_rules FROM breakpad_rw;
GRANT ALL ON TABLE transform_rules TO breakpad_rw;
GRANT SELECT ON TABLE transform_rules TO breakpad_ro;
GRANT SELECT ON TABLE transform_rules TO breakpad;
GRANT ALL ON TABLE transform_rules TO monitor;


--
-- TOC entry 4833 (class 0 OID 0)
-- Dependencies: 833
-- Name: uptime_levels; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE uptime_levels FROM PUBLIC;
REVOKE ALL ON TABLE uptime_levels FROM breakpad_rw;
GRANT ALL ON TABLE uptime_levels TO breakpad_rw;
GRANT SELECT ON TABLE uptime_levels TO breakpad_ro;
GRANT SELECT ON TABLE uptime_levels TO breakpad;
GRANT ALL ON TABLE uptime_levels TO monitor;
GRANT SELECT ON TABLE uptime_levels TO analyst;


--
-- TOC entry 4835 (class 0 OID 0)
-- Dependencies: 625
-- Name: urldims; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE urldims FROM PUBLIC;
REVOKE ALL ON TABLE urldims FROM breakpad_rw;
GRANT ALL ON TABLE urldims TO breakpad_rw;
GRANT SELECT ON TABLE urldims TO monitoring;
GRANT SELECT ON TABLE urldims TO breakpad_ro;
GRANT SELECT ON TABLE urldims TO breakpad;


--
-- TOC entry 4837 (class 0 OID 0)
-- Dependencies: 626
-- Name: urldims_id_seq1; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON SEQUENCE urldims_id_seq1 FROM PUBLIC;
REVOKE ALL ON SEQUENCE urldims_id_seq1 FROM breakpad_rw;
GRANT ALL ON SEQUENCE urldims_id_seq1 TO breakpad_rw;
GRANT SELECT ON SEQUENCE urldims_id_seq1 TO breakpad;


--
-- TOC entry 4838 (class 0 OID 0)
-- Dependencies: 831
-- Name: windows_versions; Type: ACL; Schema: public; Owner: breakpad_rw
--

REVOKE ALL ON TABLE windows_versions FROM PUBLIC;
REVOKE ALL ON TABLE windows_versions FROM breakpad_rw;
GRANT ALL ON TABLE windows_versions TO breakpad_rw;
GRANT SELECT ON TABLE windows_versions TO breakpad_ro;
GRANT SELECT ON TABLE windows_versions TO breakpad;
GRANT ALL ON TABLE windows_versions TO monitor;
GRANT SELECT ON TABLE windows_versions TO analyst;


--
-- TOC entry 3811 (class 826 OID 431251)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: -; Owner: processor
--

ALTER DEFAULT PRIVILEGES FOR ROLE processor REVOKE ALL ON SEQUENCES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE processor REVOKE ALL ON SEQUENCES  FROM processor;
ALTER DEFAULT PRIVILEGES FOR ROLE processor GRANT ALL ON SEQUENCES  TO processor;
ALTER DEFAULT PRIVILEGES FOR ROLE processor GRANT ALL ON SEQUENCES  TO breakpad_rw;


--
-- TOC entry 3813 (class 826 OID 431253)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: -; Owner: monitor
--

ALTER DEFAULT PRIVILEGES FOR ROLE monitor REVOKE ALL ON SEQUENCES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE monitor REVOKE ALL ON SEQUENCES  FROM monitor;
ALTER DEFAULT PRIVILEGES FOR ROLE monitor GRANT ALL ON SEQUENCES  TO monitor;
ALTER DEFAULT PRIVILEGES FOR ROLE monitor GRANT ALL ON SEQUENCES  TO breakpad_rw;


--
-- TOC entry 3815 (class 826 OID 736533)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: -; Owner: breakpad_rw
--

ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw REVOKE ALL ON SEQUENCES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw REVOKE ALL ON SEQUENCES  FROM breakpad_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw GRANT ALL ON SEQUENCES  TO breakpad_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw GRANT SELECT ON SEQUENCES  TO breakpad;


--
-- TOC entry 3809 (class 826 OID 183019)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON TABLES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON TABLES  FROM postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT SELECT ON TABLES  TO breakpad_ro;


--
-- TOC entry 3814 (class 826 OID 365655)
-- Dependencies: 9
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES  FROM postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES  TO breakpad;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO monitor;


--
-- TOC entry 3810 (class 826 OID 431250)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: -; Owner: processor
--

ALTER DEFAULT PRIVILEGES FOR ROLE processor REVOKE ALL ON TABLES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE processor REVOKE ALL ON TABLES  FROM processor;
ALTER DEFAULT PRIVILEGES FOR ROLE processor GRANT ALL ON TABLES  TO processor;
ALTER DEFAULT PRIVILEGES FOR ROLE processor GRANT ALL ON TABLES  TO breakpad_rw;


--
-- TOC entry 3812 (class 826 OID 431252)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: -; Owner: monitor
--

ALTER DEFAULT PRIVILEGES FOR ROLE monitor REVOKE ALL ON TABLES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE monitor REVOKE ALL ON TABLES  FROM monitor;
ALTER DEFAULT PRIVILEGES FOR ROLE monitor GRANT ALL ON TABLES  TO monitor;
ALTER DEFAULT PRIVILEGES FOR ROLE monitor GRANT ALL ON TABLES  TO breakpad_rw;


--
-- TOC entry 3816 (class 826 OID 736534)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: -; Owner: breakpad_rw
--

ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw REVOKE ALL ON TABLES  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw REVOKE ALL ON TABLES  FROM breakpad_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw GRANT ALL ON TABLES  TO breakpad_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE breakpad_rw GRANT SELECT ON TABLES  TO breakpad;


-- Completed on 2012-04-11 12:47:31 PDT

--
-- PostgreSQL database dump complete
--

