db = db.getSiblingDB('payment-service-db');

db.createUser({
  user: 'payment-service-db-user',
  pwd: 'dbinitPASSWORD001axi00',
  roles: [{ role: 'readWrite', db: 'payment-service-db' }],
});
