class Point {
  BigInt x;
  BigInt y;

  Point(this.x, this.y);
}

class EllipticCurve {
  late BigInt p;
  late BigInt a;
  late BigInt b;
  late Point G;
  late BigInt n; // n is prime and is the "order" of G
  late BigInt h; // h = #E(F_p)/n (# is the number of points on the curve)

  EllipticCurve();
}

class EccKey {
  BigInt d; // random integer < n; this is the private key
  Point Q; // Q = d * G; this is the public key

  EccKey(this.d, this.Q);
}

void add_points(Point p1, Point p2, BigInt p) {
  Point p3;
  BigInt denominator;
  BigInt numerator;
  BigInt invdenom;
  BigInt lambda;

//   set_huge( &denominator, 0 );
//   copy_huge( &denominator, &p2->x );    // denominator = x2
//   subtract( &denominator, &p1->x );     // denominator = x2 - x1
  denominator = p2.x - p1.x; // denominator = x2 - x1 {Kelly}
//   set_huge( &numerator, 0 );
//   copy_huge( &numerator, &p2->y );      // numerator = y2
//   subtract( &numerator, &p1->y );       // numerator = y2 - y1
  numerator = p2.y - p1.y;
//   set_huge( &invdenom, 0 );
//   copy_huge( &invdenom, &denominator );
//   inv( &invdenom, p );
  invdenom = denominator.modInverse(BigInt.from(1));
//   set_huge( &lambda, 0 );
//   copy_huge( &lambda, &numerator );
//   multiply( &lambda, &invdenom );       // lambda = numerator / denominator
  lambda = numerator * invdenom;
//   set_huge( &p3.x, 0 );
//   copy_huge( &p3.x, &lambda );    // x3 = lambda
//   multiply( &p3.x, &lambda );     // x3 = lambda * lambda
//   subtract( &p3.x, &p1->x );      // x3 = ( lambda * lambda ) - x1
//   subtract( &p3.x, &p2->x );      // x3 = ( lambda * lambda ) - x1 - x2

//   divide( &p3.x, p, NULL );       // x3 = ( ( lamdba * lambda ) - x1 - x2 ) % p

  final x3 = ((lambda * lambda) - p2.x - p2.x) ~/ p;

//   // positive remainder always
//   if ( p3.x.sign )
//   {
//     p3.x.sign = 0;
//     subtract( &p3.x, p );
//     p3.x.sign = 0;
//   }

//   set_huge( &p3.y, 0 );
//   copy_huge( &p3.y, &p1->x );    // y3 = x1
//   subtract( &p3.y, &p3.x );      // y3 = x1 - x3
//   multiply( &p3.y, &lambda );    // y3 = ( x1 - x3 ) * lambda
//   subtract( &p3.y, &p1->y );     // y3 = ( ( x1 - x3 ) * lambda ) - y
  final y3 = ((p2.x - x3) * lambda) - p1.y;

  p3 = Point(x3, y3);

//   divide( &p3.y, p, NULL );
//   // positive remainder always
//   if ( p3.y.sign )
//   {
//     p3.y.sign = 0;
//     subtract( &p3.y, p );
//     p3.y.sign = 0;
//   }

//   // p1->x = p3.x
//   // p1->y = p3.y
//   copy_huge( &p1->x, &p3.x );
//   copy_huge( &p1->y, &p3.y );

//   free_huge( &p3.x );
//   free_huge( &p3.y );
//   free_huge( &denominator );
//   free_huge( &numerator );
//   free_huge( &invdenom );
//   free_huge( &lambda );
}

void double_point(Point p1, BigInt a, BigInt p) {
  BigInt lambda;
  BigInt l1;
  BigInt x1;
  BigInt y1;

  // set_huge( &lambda, 0 );
  lambda = BigInt.from(0);
  // set_huge( &x1, 0 );
  x1 = BigInt.from(0);
  // set_huge( &y1, 0 );
  y1 = p1.y;
  // set_huge( &lambda, 2 );     // lambda = 2;
  lambda = BigInt.from(2);
  // multiply( &lambda, &p1->y );  // lambda = 2 * y1
  lambda = lambda * p1.y;
  // inv( &lambda, p );       // lambda = ( 2 * y1 ) ^ -1 (% p)
  lambda = lambda.modInverse(p);

  // set_huge( &l1, 3 );       // l1 = 3
  l1 = BigInt.from(3);
  // multiply( &l1, &p1->x );    // l1 = 3 * x
  l1 = l1 * p1.x;
  // multiply( &l1, &p1->x );    // l1 = 3 * x ^ 2
  l1 = l1 * p1.x;
  // add( &l1, a );         // l1 = ( 3 * x ^ 2 ) + a
  l1 = l1 + a;
  // multiply( &lambda, &l1 );    // lambda = [ ( 3 * x ^ 2 ) + a ] / [ 2 * y1 ] ) % p
  lambda = lambda * l1;
  // copy_huge( &y1, &p1->y );
  y1 = p1.y;
  // // Note - make two copies of x2; this one is for y1 below
  // copy_huge( &p1->y, &p1->x );
  p1.y = p1.x;
  // set_huge( &x1, 2 );
  x1 = BigInt.from(2);
  // multiply( &x1, &p1->x );    // x1 = 2 * x1
  x1 = x1 * p1.x;

  // copy_huge( &p1->x, &lambda );  // x1 = lambda
  p1.x = lambda;
  // multiply( &p1->x, &lambda );  // x1 = ( lambda ^ 2 );
  p1.x = p1.x * lambda;
  // subtract( &p1->x, &x1 );    // x1 = ( lambda ^ 2 ) - ( 2 * x1 )
  p1.x = p1.x - x1;
  // divide( &p1->x, p, NULL );   // [ x1 = ( lambda ^ 2 ) - ( 2 * x1 ) ] % p
  p1.x = p1.x ~/ p;

  // if ( p1->x.sign )
  // {
  //   subtract( &p1->x, p );
  //   p1->x.sign = 0;
  //   subtract( &p1->x, p );
  // }
  // subtract( &p1->y, &p1->x );  // y3 = x3 � x1
  // multiply( &p1->y, &lambda ); // y3 = lambda * ( x3 - x1 );
  // subtract( &p1->y, &y1 );   // y3 = ( lambda * ( x3 - x1 ) ) - y1
  // divide( &p1->y, p, NULL );  // y3 = [ ( lambda * ( x3 - x1 ) ) - y1 ] % p
  // if ( p1->y.sign )
  // {
  //   p1->y.sign = 0;
  //   subtract( &p1->y, p );
  //   p1->y.sign = 0;
  // }

  // free_huge( &lambda );
  // free_huge( &x1 );
  // free_huge( &y1 );
  // free_huge( &l1 );
}
