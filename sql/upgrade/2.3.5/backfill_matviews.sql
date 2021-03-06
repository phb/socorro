DROP FUNCTION backfill_matviews ( date, text, date, boolean);

\set ON_ERROR_STOP 1

-- function

CREATE OR REPLACE FUNCTION backfill_matviews (
	firstday date,
	lastday date default NULL,
	reportsclean boolean default true )
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $f$
DECLARE thisday DATE := firstday;
BEGIN
-- this producedure is meant to be called manually
-- by administrators in order to clear and backfill
-- the various matviews in order to recalculate old
-- data which was erroneous.
-- it requires a start date, and optionally an end date
-- no longer takes a product parameter
-- optionally disable reports_clean backfill
-- since that takes a long time

-- VERSION 0.3

-- set optional end date
lastday := coalesce(lastday, current_date );

-- check parameters
IF firstday > current_date OR lastday > current_date or firstday > lastday THEN
	RAISE EXCEPTION 'date parameter error: cannot backfill into the future';
END IF;

-- fill in products
PERFORM update_product_versions();

-- backfill reports_clean.  this takes a while,  and isn't limited
-- by product so if it's not needed
-- we provide a switch to disable it
IF reportsclean THEN
	RAISE INFO 'backfilling reports_clean';
	PERFORM backfill_reports_clean_by_date( firstday, lastday );
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

	thisday := thisday + 1;

END LOOP;

RETURN true;
END; $f$;


