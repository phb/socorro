import logging
import psycopg2

from socorro.external.postgresql.base import PostgreSQLBase
from socorro.lib import external_common

import socorro.database.database as db

logger = logging.getLogger("webapi")


class MissingOrBadArgumentError(Exception):
    pass


class Bugs(PostgreSQLBase):
    """Implement the /bugs service with PostgreSQL. """

    def get(self, **kwargs):
        """Return a list of signature - bug id associations. """
        filters = [
            ("signatures", None, ["list", "str"]),
        ]
        params = external_common.parse_arguments(filters, kwargs)

        if not params.signatures:
            raise MissingOrBadArgumentError(
                        "Mandatory parameter 'signatures' is missing or empty")

        # Preparing variables for the SQL query
        signatures = []
        sql_params = {}
        for i, elem in enumerate(params.signatures):
            signatures.append("%%(signature%s)s" % i)
            sql_params["signature%s" % i] = elem

        sql = """/* socorro.external.postgresql.bugs.Bugs.get */
            SELECT ba.signature, bugs.id
            FROM bugs
                JOIN bug_associations AS ba ON bugs.id = ba.bug_id
            WHERE EXISTS(
                SELECT 1 FROM bug_associations
                WHERE bug_associations.bug_id = bugs.id
                AND signature IN (%s)
            )
        """ % ", ".join(signatures)
        sql = str(" ".join(sql.split()))  # better formatting of the sql string

        connection = None

        try:
            connection = self.database.connection()
            cur = connection.cursor()
            #~ logger.debug(cur.mogrify(sql, sql_params))
            results = db.execute(cur, sql, sql_params)
        except psycopg2.Error:
            logger.error("Failed retrieving extensions data from PostgreSQL",
                         exc_info=True)
        else:
            result = {
                "total": 0,
                "hits": []
            }

            for crash in results:
                row = dict(zip(("signature", "id"), crash))
                result["hits"].append(row)
            result["total"] = len(result["hits"])

            return result
        finally:
            if connection:
                connection.close()
