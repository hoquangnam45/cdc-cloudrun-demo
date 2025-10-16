-- Database initialization script
-- This file is automatically executed by Hibernate during schema creation
-- Works in all environments (dev, test, prod)

-- Insert sample MyEntity records
INSERT INTO MyEntity (id, field) VALUES (1, 'Sample field 1');
INSERT INTO MyEntity (id, field) VALUES (2, 'Sample field 2');
INSERT INTO MyEntity (id, field) VALUES (3, 'Sample field 3');
INSERT INTO MyEntity (id, field) VALUES (4, 'Sample field 4');
INSERT INTO MyEntity (id, field) VALUES (5, 'Sample field 5');

-- Insert sample Message records
INSERT INTO Message (id, content) VALUES (1, 'Hello from Quarkus Cloud Run!');
INSERT INTO Message (id, content) VALUES (2, 'Testing JVM vs Native performance');
INSERT INTO Message (id, content) VALUES (3, 'Direct connection to Cloud SQL');
INSERT INTO Message (id, content) VALUES (4, 'Using PgBouncer for connection pooling');
INSERT INTO Message (id, content) VALUES (5, 'Jib makes container builds easy!');

-- Reset sequences to continue from the last inserted ID
ALTER SEQUENCE MyEntity_SEQ RESTART WITH 6;
ALTER SEQUENCE Message_SEQ RESTART WITH 6;
