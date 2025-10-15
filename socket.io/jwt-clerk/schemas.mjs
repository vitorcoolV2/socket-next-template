import Joi from 'joi';
// Supported algorithms for JWT validation
const supportedAlgorithms = ['RS256', 'RS384', 'RS512']; // TODO: Add 'ES256', 'ES384', 'ES512' later


// Algorithm schema
const algSchema = Joi.string().valid(...supportedAlgorithms);

// JWKS Key schema
const jwksKeySchema = Joi.object({
  kty: Joi.string().valid('RSA').required(),
  use: Joi.string().valid('sig').required(),
  kid: Joi.string().required(),
  alg: algSchema.required(),
  n: Joi.string().required(),
  e: Joi.string().required(),
});

// Passport schema
const passportSchema = Joi.object({
  keys: Joi.array().items(jwksKeySchema).optional(),
  roles: Joi.array().items(Joi.string()).optional(),
  iss: Joi.string().uri().required(),
  aud: Joi.array().items(Joi.string()).min(1).required().messages({
    'array.min': 'Passport audience (aud) must contain at least one item',
    'any.required': 'Passport audience (aud) is required',
  }),
  exp: Joi.number().optional(),
  ignoreExpiration: Joi.boolean()
    .optional()
    .default(true)
    .description('If true, token expiration (exp) will be ignored during validation'),
  ignoreNotBefore: Joi.boolean()
    .optional()
    .default(true)
    .description('If true, token not-before (nbf) will be ignored during validation'),
  algorithms: Joi.array().items(algSchema.clone()).optional().description('Allowed algorithms, e.g., RS256'),
  nbf: Joi.number().optional().description('Not Before claim'),
  sub: Joi.string().optional().description('Subject claim'),
  jti: Joi.string().optional().description('JWT ID claim'),
  roles: Joi.array()
    .items(Joi.string().valid('user', 'admin'))
    .optional()
    .description('Allowed roles'),
});

export { algSchema, jwksKeySchema, passportSchema, supportedAlgorithms };