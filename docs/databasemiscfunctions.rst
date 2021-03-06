.. index:: database

.. _databasemiscfunctions-chapter:

Database Misc Function Reference
================================

What follows is a listing of custom functions written for Socorro in the
PostgreSQL database which are useful for application development, but
do not fit in the "Admin" or "Datetime" categories.

Formatting Functions
====================

build_numeric
-------------

::

	build_numeric (
		build TEXT
	)
	RETURNS NUMERIC
		
	SELECT build_numeric ( '20110811165603' );
	
Converts a build ID string, as supplied by the processors/breakpad, into 
a numeric value on which we can do computations and derive a date.  Returns
NULL if the build string is a non-numeric value and thus corrupted.


build_date
----------

::

	build_date (
		buildid NUMERIC
	)
	RETURNS DATE
	
	SELECT build_date ( 20110811165603 );
	
Takes a numeric build_id and returns the date of the build.


API Functions
=============

These functions support the middleware, making it easier to look up
certain things in the database.

get_product_version_ids
------------------------

::

	get_product_version_ids (
		product CITEXT,
		versions VARIADIC CITEXT
	)
	
	SELECT get_product_version_ids ( 'Firefox','11.0a1' );
	SELECT get_product_version_ids ( 'Firefox','11.0a1','11.0a2','11.0b1');
	
Takes a product name and a list of version_strings, and returns an array (list) of surrogate keys (product_version_ids) which can then be used in queries like:

::

	SELECT * FROM reports_clean WHERE date_processed BETWEEN '2012-03-21' AND '2012-03-38' 
	WHERE product_version_id = ANY ( $list );
	
	
		
		





