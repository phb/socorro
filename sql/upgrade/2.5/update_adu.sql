\set ON_ERROR_STOP 1

-- function

CREATE OR REPLACE FUNCTION update_adu (
	updateday date, checkdata boolean default true )
RETURNS BOOLEAN
LANGUAGE plpgsql
SET work_mem = '512MB'
SET temp_buffers = '512MB'
AS $f$
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
END; $f$;

CREATE OR REPLACE FUNCTION backfill_adu (
	updateday date )
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $f$
BEGIN
-- stored procudure to delete and replace one day of
-- product_adu, optionally only for a specific product
-- intended to be called by backfill_matviews

DELETE FROM product_adu 
WHERE adu_date = updateday;

PERFORM update_adu(updateday);

RETURN TRUE;
END; $f$;

\set ON_ERROR_STOP 0

DROP FUNCTION backfill_adu( date, text );
DROP FUNCTION update_adu(date);






